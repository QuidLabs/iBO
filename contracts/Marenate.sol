//SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity =0.8.8;

import "./Moulinette.sol";
import "hardhat/console.sol"; // TODO comment out

import "./Dependencies/VRFConsumerBaseV2.sol";
import "./Dependencies/VRFCoordinatorV2Interface.sol";
import "./Dependencies/AggregatorV3Interface.sol";
import "./Dependencies/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface ICollection is IERC721 {
    function latestTokenId() external view returns (uint);
}

interface LinkTokenInterface is IERC20 {
    function decreaseApproval(address spender, uint addedValue) external returns (bool success);
    function increaseApproval(address spender, uint subtractedValue) external;
    function transferAndCall(address to, uint value, bytes calldata data) external returns (bool success);
}

contract Marenate is 
    VRFConsumerBaseV2, 
    IERC721Receiver { 
    bool public PAUSED; 
    uint public minDuration;
    uint public minLiquidity;
    uint public last_lotto_trigger;
    uint public immutable DEPLOYED; 
    
    int24 internal constant MAX_TICK = 887272;
    int24 internal constant MIN_TICK = -887272;
    uint internal constant HOURS_PER_WEEK = 168;
    
    event NewMinLiquidity(uint liquidity);
    event NewMinDuration(uint duration);
    event RequestedRandomness(uint requestId);
    VRFCoordinatorV2Interface COORDINATOR;
    LinkTokenInterface LINK; bytes32 keyHash;

    uint64 public subscriptionId;
    address public owed;
    address public driver; 
    uint32 callbackGasLimit;
    uint16 requestConfirmations;
    uint public requestId; 
    uint randomness; // 🎲
    Moulinette MO; // MO = Modus Operandi 

    event DepositETH(address sender, uint amount);
    event DepositNFT(uint tokenId, address owner);
    event Withdrawal(uint tokenId, address owner);
    // withdrawal may either burn the NFT and release funds to the owner
    // or keeps the funds inside the NFT and transfer it back to the owner
    mapping(address => mapping(uint => uint)) public depositTimestamps; // owner => NFTid => timestamp
    // Depositors can have multiple positions, representing different price ranges (ticks)
    // if they never pick, there should be at least one depositId (for the full tick range)
    struct NFT {
        bool burned;
        uint id;
    }
    mapping(address => NFT[]) public usdcIDs; 
    mapping(uint => uint) public totalsUSDC; // week # -> snapshot of liquidity
    uint public weeklyRewardUSDC; // in units of USDC
    uint public liquidityUSDC; // total for all LP deposits
    uint public maxTotalUSDC; // in UniV3 liquidity units
    uint24 public FEE_USDC = 0; 

    event NewWeeklyRewardUSDC(uint reward);
    event NewMaxTotalUSDC(uint total);
    uint constant public LAMBO = 16508; // youtu.be/sitXeGjm4Mc 
    uint constant public LOTTO = 608358 * 1e18;
    uint constant public MIN_APR = 120000000000000000; // copy-pasted from Moulinette
    uint constant public PENNY = WAD / 100;
    uint constant public WAD = 1e18; 
    
    // Pools address (mainnet), may be updated by MSIG owners
    address public QUID_USDC = 0xe081EEAB0AdDe30588bA8d5B3F6aE5284790F54A; // TODO change after creating UniV3 pool
    address constant public NFPM = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88; // Uniswap
    // Chainlink
    address constant public ETH_PRICE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant public SOL_PRICE = 0x4ffC43a60e009B551865A93d232E33Fce9f01507;
    // foundation
    address constant public F8N_0 = 0x3B3ee1931Dc30C1957379FAc9aba94D1C48a5405; // can only test 
    address constant public F8N_1 = 0x0299cb33919ddA82c72864f7Ed7314a3205Fb8c4; // on mainnet :)
    // ERC20 addresses
    address constant public QUID = 0x42cc020Ef5e9681364ABB5aba26F39626F1874A4;
    address constant public USDC = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // https://www.instagram.com/p/C7Pkn1MtbUc
    uint[31] internal feeTargets; struct Medianiser { 
        uint apr; // most recent weighted median fee 
        uint[31] weights; // sum weights for each fee
        uint total; // _POINTS > sum of ALL weights... 
        uint sum_w_k; // sum(weights[0..k]) sum of sums
        uint k; // approximate index of median (+/- 1)
    } Medianiser public longMedian; // between 12-27%
    Medianiser public shortMedian; // 2 distinct fees
    event NewMedian(uint oldMedian, uint newMedian, bool long);

    struct Transfer {
        address to;
        uint value;
        address token;
        bool executed;
        uint confirm;
    }   Transfer[] public transfers;
    mapping(uint => mapping(address => bool)) public confirmed;
    mapping(address => bool) public isOwner;
  
    event SubmitTransfer(
        address indexed owner,
        uint indexed index,
        address indexed to,
        uint value
    );
    event ConfirmTransfer(address indexed owner, uint indexed index);
    event RevokeTransfer(address indexed owner, uint indexed index);
    event ExecuteTransfer(address indexed owner, uint indexed index);
    
    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier exists(uint _index) {
        require(_index < transfers.length, "does not exist");
        _;
    }

    modifier notExecuted(uint _index) {
        require(!transfers[_index].executed, "already executed");
        _;
    }

    modifier notConfirmed(uint _index) {
        require(!confirmed[_index][msg.sender], "already confirmed");
        _;
    }
    
    function getMedian(bool short) external view returns (uint) {
        if (short) { return shortMedian.apr; } 
        else { return longMedian.apr; }
    }

    /** 
     * Returns the latest price obtained from the Chainlink ETH:USD aggregator 
     * reference contract...https://docs.chain.link/docs/get-the-latest-price
     */
    function getPrice(bool eth) external view returns (uint price) {
        AggregatorV3Interface chainlink; 
        if (eth) {
            chainlink = AggregatorV3Interface(ETH_PRICE);
        } else {
            chainlink = AggregatorV3Interface(SOL_PRICE);
        }
        (, int priceAnswer,, uint timeStamp,) = chainlink.latestRoundData();
        require(timeStamp > 0 && timeStamp <= block.timestamp 
                && priceAnswer >= 0, "MO::price");
        uint8 answerDigits = chainlink.decimals();
        price = uint(priceAnswer);
        // currently the Aggregator returns an 8-digit precision, but we handle the case of future changes
        if (answerDigits > 18) { price /= 10 ** (answerDigits - 18); }
        else if (answerDigits < 18) { price *= 10 ** (18 - answerDigits); } 
    }

    receive() external payable { // receive from MO
        emit DepositETH(msg.sender, msg.value);
    }  
    fallback() external payable {}
    
    function _min(uint _a, uint _b) internal pure returns (uint) {
        return (_a < _b) ? _a : _b;
    }

    function toggleStaking() external onlyOwner {
        PAUSED = !PAUSED;
    }

    // This is rarely (if ever) called, when (if) 
    // a new pool is created (with a new fee)... 
    function setPool(uint24 fee, address poolAddress) 
        external onlyOwner {
        FEE_USDC = fee; QUID_USDC = poolAddress;
    }

    // rollOver past weeks' snapshots of total liquidity to this week
    function _roll() internal returns (uint current_week) { 
        current_week = (block.timestamp - DEPLOYED) / 1 weeks;
        totalsUSDC[current_week] = liquidityUSDC;
    }

    function setMinLiquidity(uint128 _minLiquidity) external onlyOwner {
        minLiquidity = _minLiquidity;
        emit NewMinLiquidity(_minLiquidity);
    }

    /**
     * @dev Update the minimum lock duration for staked LP tokens.
     * @param _newDuration New minimum lock duration (in weeks)
     */
    function setMinDuration(uint _newDuration) external onlyOwner {
        require(_newDuration % 1 weeks == 0 && minDuration / 1 weeks >= 1, 
        "Duration must be in units of weeks");
        minDuration = _newDuration;
        emit NewMinDuration(_newDuration);
    }

    /**
     * @dev Update the weekly reward. Amount in USDC
     * @param _newReward New weekly reward.
     */
    function setWeeklyRewardUSDC(uint _newReward) external onlyOwner {
        weeklyRewardUSDC = _newReward;
        emit NewWeeklyRewardUSDC(_newReward);
    }

    /**
     * @dev Update the maximum liquidity the vault may hold (for the QD<>USDC pair).
     * The purpose is to increase the amount gradually, so as to not dilute the APY
     * unnecessarily much in beginning.
     * @param _newMaxTotal New max total.
     */
    function setMaxTotalUSDC(uint128 _newMaxTotal) external onlyOwner {
        maxTotalUSDC = _newMaxTotal;
        emit NewMaxTotalUSDC(_newMaxTotal);
    }

    function submitTransfer(address _to, 
        uint _value, address _token)
        public onlyOwner {
        require(_token == MO.SFRAX() 
            || _token == MO.SDAI(), 
            "MO::bad address"
        );
        uint index = transfers.length;
        transfers.push(
            Transfer({to: _to,
                value: _value,
                token: _token,
                executed: false,
                confirm: 0
            })
        );  emit SubmitTransfer(msg.sender, index, 
                                _to, _value);
    }

    function confirmTransfer(uint _index) 
        public onlyOwner exists(_index)
        notExecuted(_index) notConfirmed(_index) {
        Transfer storage transfer = transfers[_index];
        transfer.confirm += 1;
        confirmed[_index][msg.sender] = true;
        emit ConfirmTransfer(msg.sender, _index);
    }

    function executeTransfer(uint _index)
        public onlyOwner exists(_index)
        notExecuted(_index) {
        Transfer storage transfer = transfers[_index];
        require(transfer.confirm >= 3, "cannot execute tx");
        IERC20(transfer.token).transfer( 
            transfer.to, transfer.value);  
            transfer.executed = true; 
        emit ExecuteTransfer(msg.sender, _index);
    }
    
    // bytes32 s_keyHash: The gas lane key hash value,
    // which is the maximum gas price you are willing to
    // pay for a request in wei. It functions as an ID 
    // of the offchain VRF job that runs in onReceived.
    constructor(address[] memory _owners, 
                address _vrf, address _link, bytes32 _hash, 
                uint32 _limit, uint16 _confirm, address _mo) 
                VRFConsumerBaseV2(_vrf) { MO = Moulinette(_mo); 

        for (uint i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner not unique");
            isOwner[owner] = true;
        } 
        maxTotalUSDC = type(uint).max;
        weeklyRewardUSDC = 100000; // 10 cents per unit of liquidity staked
        minDuration = MO.LENT(); keyHash = _hash;
        LINK = LinkTokenInterface(_link); 
        requestConfirmations = _confirm;
        callbackGasLimit = _limit; 
        FEE_USDC = 10000; 
        minLiquidity = 0;
        
        DEPLOYED = block.timestamp; owed = msg.sender;
        COORDINATOR = VRFCoordinatorV2Interface(_vrf);    
        COORDINATOR.addConsumer(subscriptionId, address(this));
        subscriptionId = COORDINATOR.createSubscription(); // pubsub
        feeTargets = [MIN_APR, 125000000000000000,130000000000000000, 
          135000000000000000, 140000000000000000, 145000000000000000, 
          150000000000000000, 155000000000000000, 160000000000000000, 
          165000000000000000, 170000000000000000, 175000000000000000, 
          180000000000000000, 185000000000000000, 190000000000000000, 
          195000000000000000, 200000000000000000, 205000000000000000,
          210000000000000000, 215000000000000000, 220000000000000000, 
          225000000000000000, 230000000000000000, 235000000000000000, 
          240000000000000000, 245000000000000000, 250000000000000000, 
          255000000000000000, 260000000000000000, 265000000000000000, 
          270000000000000000]; uint[31] memory blank; // no more than a credit card
        longMedian = Medianiser(MIN_APR, blank, 0, 0, 0);
        shortMedian = Medianiser(MIN_APR, blank, 0, 0, 0); 
    }

     /** To be responsive to DSR changes we have dynamic APR 
     *  using a points-weighted median algorithm for voting:
     *  not too dissimilar github.com/euler-xyz/median-oracle
     *  Find value of k in range(0, len(Weights)) such that 
     *  sum(Weights[0:k]) = sum(Weights[k:len(Weights)+1])
     *  = sum(Weights) / 2
     *  If there is no such value of k, there must be a value of k 
     *  in the same range range(0, len(Weights)) such that 
     *  sum(Weights[0:k]) > sum(Weights) / 2
     *  TODO update total points only here ? 
     */ 
    function medianise(uint new_stake, uint new_vote, 
        uint old_stake, uint old_vote, bool short) external { 
        require(msg.sender == address(MO), "unauthorized");
        uint delta = MIN_APR / 16; 
        Medianiser memory data = short ? shortMedian : longMedian;
        // when k = 0 it has to be 
        if (old_vote != 0 && old_stake != 0) { // clear old values
            uint old_index = (old_vote - MIN_APR) / delta;
            data.weights[old_index] -= old_stake;
            data.total -= old_stake;
            if (old_vote <= data.apr) {   
                data.sum_w_k -= old_stake;
            }
        } uint index = (new_vote 
            - MIN_APR) / delta;
        if (new_stake != 0) {
            data.total += new_stake;
            if (new_vote <= data.apr) {
                data.sum_w_k += new_stake;
            }		  
            data.weights[index] += new_stake;
        } uint mid_stake = data.total / 2;
        if (data.total != 0 && mid_stake != 0) {
            if (data.apr > new_vote) {
                while (data.k >= 1 && (
                     (data.sum_w_k - data.weights[data.k]) >= mid_stake
                )) { data.sum_w_k -= data.weights[data.k]; data.k -= 1; }
            } else {
                while (data.sum_w_k < mid_stake) { data.k += 1;
                       data.sum_w_k += data.weights[data.k];
                }
            } data.apr = feeTargets[data.k];
            if (data.sum_w_k == mid_stake) { 
                uint intermedian = data.apr + ((data.k + 1) * delta) + MIN_APR;
                data.apr = intermedian / 2;  
            }
        }  else { data.sum_w_k = 0; } 
        if (!short) { longMedian = data; 
            if (longMedian.apr != data.apr) { 
                emit NewMedian(longMedian.apr, data.apr, true);
            } // emit yo fee = truth & beauty in Hebrew :)
        } 
        else { shortMedian = data; 
            if (shortMedian.apr != data.apr) {
                emit NewMedian(shortMedian.apr, data.apr, false);
            }
        }
    }

    /** Whenever an {IERC721} `tokenId` token is transferred to this contract:
     * @dev Safe transfer `tokenId` token from `from` to `address(this)`, 
     * checking that contract recipient prevent tokens from being forever locked.
     * - `tokenId` token must exist and be owned by `from`
     * - If the caller is not `from`, it must have been allowed 
     *   to move this token by either {approve} or {setApprovalForAll}.
     * - {onERC721Received} is called after a safeTransferFrom...
     * - It must return its Solidity selector to confirm the token transfer.
     *   If any other value is returned or the interface is not implemented
     *   by the recipient, the transfer will be reverted.
     */
    // QuidMint...foundation.app/@quid
    function onERC721Received(address, 
        address from, // previous owner's
        uint tokenId, bytes calldata data
    ) external override returns (bytes4) { bool refund = false;
        require(MO.SEMESTER() > last_lotto_trigger, "early"); 
        uint shirt = ICollection(F8N_1).latestTokenId(); 
        address parked = ICollection(F8N_0).ownerOf(LAMBO);
        address racked = ICollection(F8N_1).ownerOf(shirt);
        if (tokenId == LAMBO && parked == address(this)) {
            driver = from; payout(driver, LOTTO);
        }   else if (tokenId == shirt && racked == address(this)) {
                require(parked == address(this), "chronology");
                require(from == owed, "MA::wrong winner");
                last_lotto_trigger = MO.SEMESTER();
                ICollection(F8N_0).transferFrom(
                    address(this), driver, LAMBO);
                uint most = _min(MO.balanceOf(address(this)), LOTTO); 
                require(MO.transfer(owed, most), "MA::QD"); 
                requestId = COORDINATOR.requestRandomWords(
                    keyHash, subscriptionId,
                    requestConfirmations,
                    callbackGasLimit, 1
                );  emit RequestedRandomness(requestId);
        }   else { refund = true; }
        if (!refund) { return this.onERC721Received.selector; }
        else { return 0; }
    }

    function payout(address to, uint amount) internal {
        uint sfrax = IERC20(MO.SFRAX()).balanceOf(address(this));
        uint sdai = IERC20(MO.SDAI()).balanceOf(address(this));
        uint total = sfrax + sdai;
        uint actual = _min(total, amount);
        if (sfrax > sdai) {
            sfrax = _min(sfrax, actual); uint delta = actual - sfrax;
            require(IERC20(MO.SFRAX()).transfer(to, sfrax), "MA::sFRAX");
            require(IERC20(MO.SDAI()).transfer(to, delta), "MA::sDAI");
        } else {
            sdai = _min(sdai, actual); uint delta = actual - sdai;
            require(IERC20(MO.SDAI()).transfer(to, sdai), "MA::sDAI");
            require(IERC20(MO.SFRAX()).transfer(to, delta), "MA::sFRAX");
        }
    }

    function cede(address to) external onlyOwner { // cede authority
        address parked = ICollection(F8N_0).ownerOf(LAMBO);
        require(parked == address(this), "wait for it");
        require(isOwner[msg.sender], "caller not an owner");
        require(!isOwner[to], "owner not unique");
        require(to != address(0), "invalid owner");
        isOwner[msg.sender] = false;
        isOwner[to] = true;  
    } 
    
    function fulfillRandomWords(uint _requestId, 
        uint[] memory randomWords) internal override { 
        randomness = randomWords[0]; uint when = MO.SEMESTER() - 1; 
        uint shirt = ICollection(F8N_1).latestTokenId(); 
        address racked = ICollection(F8N_1).ownerOf(shirt);
        require(randomness > 0 && _requestId > 0 // secret
        && _requestId == requestId && // are we who we are
        address(this) == racked, "MA::randomWords"); 
        address[] memory owned = MO.liquidated(when);
        uint indexOfWinner = randomness % owned.length;
        owed = owned[indexOfWinner]; // quip captured
        ICollection(F8N_1).transferFrom( // 
            address(this), owed, shirt
        ); // next winner pays deployer
    }
   
    /**
     * @dev Unstake UniV3 LP deposit from vault (changing the owner back to original)
     */
    function withdrawToken(uint tokenId, bool burn) external {
        require(!PAUSED, "Marenate::deposit: contract paused");
        uint timestamp = depositTimestamps[msg.sender][tokenId]; 
        require(timestamp > 0, "Marenate::withdraw: no deposit");
        require( // how long this deposit has been in the vault
            (block.timestamp - timestamp) > minDuration,
            "Marenate::withdraw: not yet"
        );
        (,, address token0,,,,, uint128 liquidity,,,,) = INonfungiblePositionManager(NFPM).positions(tokenId);
        uint current_week = _roll(); NFT memory nft;
        uint reward = _reward(timestamp, liquidity, 
                              token0, current_week);
        if (burn) {
            IERC20(token0).transfer(msg.sender, reward);
            // this makes all of the liquidity collectable in the next function call
            INonfungiblePositionManager(NFPM).decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams(tokenId, liquidity,
                                                                    0, 0, block.timestamp));
            _collect(tokenId, msg.sender, 0, 0);
            INonfungiblePositionManager(NFPM).burn(tokenId);
        } 
        else {
            // increase liquidity of the NFT using collected fees and the reward
            _collect(tokenId, address(this), reward, 0); 
            // transfer ownership back to the original LP token owner
            INonfungiblePositionManager(NFPM).transferFrom(address(this), msg.sender, tokenId);
        }
        liquidityUSDC -= liquidity;
        for (uint i = 0; i < usdcIDs[msg.sender].length; i++) {
            nft = usdcIDs[msg.sender][i];
            if (nft.id == tokenId) {
                usdcIDs[msg.sender][i].burned = true;
            }
        }
        delete depositTimestamps[msg.sender][tokenId];
        emit Withdrawal(tokenId, msg.sender);
    }

    // depositors must call this individually at their leisure
    // rewards will be re-deposited into their respective NFTs
    function compound(address beneficiary) external {
        require(!PAUSED, "Marenate::deposit: paused");
        uint i; uint amount; uint timestamp; 
        uint tokenId; NFT memory nft; 
        uint current_week = _roll();
        for (i = 0; i < usdcIDs[beneficiary].length; i++) {
            nft = usdcIDs[beneficiary][i];
            if (nft.burned) {
                continue;
            }
            tokenId = nft.id;
            (,,,,,,,uint128 liquidity,,,,) = INonfungiblePositionManager(NFPM).positions(tokenId);
            timestamp = depositTimestamps[msg.sender][tokenId]; 
            // amount to draw from address(this) and deposit into NFT position
            amount = _reward(timestamp, liquidity, USDC, current_week);
            depositTimestamps[msg.sender][tokenId] = block.timestamp; 
           
            liquidityUSDC -= liquidity; // reward + collected fees from uniswap
            liquidityUSDC += _collect(tokenId, address(this), amount, 0); // ++
        }
    }

    function _collect(uint tokenId, address receiver, 
        uint amountA, uint amountB) internal returns (uint128 liquidity) {
        (uint amount0, uint amount1) = INonfungiblePositionManager(NFPM).collect(
            INonfungiblePositionManager.CollectParams(tokenId, 
                receiver, type(uint128).max, type(uint128).max)
        );
        if (receiver == address(this)) { // not a withdrawal
            amount0 += amountA; amount1 += amountB;
            if (amount1 > 0) {
                IERC20(QUID).approve(NFPM, amount1);
            }
            if (amount0 > 0) {
                IERC20(USDC).approve(NFPM, amount0);
            }
            (liquidity,,) = INonfungiblePositionManager(NFPM).increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(tokenId,
                                    amount0, amount1, 0, 0, block.timestamp));
        }
    }

    // timestamp (input variable) indicates when reward was last collected
    function _reward(uint timestamp, uint liquidity, 
        address token0, uint current_week) 
        internal returns (uint totalReward) {
        // when had the NFT deposit been made
        // relative to the time when contract was deployed
        uint week_iterator = (timestamp - DEPLOYED) / 1 weeks;
        // could've deposited right before the end of the week, so need a bit of granularity
        // otherwise an unfairly large portion of rewards may be obtained by staker
        uint so_far = (timestamp - DEPLOYED) / 1 hours;
        uint delta = so_far + (week_iterator * HOURS_PER_WEEK);
        // the 1st reward may be a fraction of a whole week's worth
        uint reward = (delta * weeklyRewardUSDC) / HOURS_PER_WEEK; 
        while (week_iterator < current_week) {
            uint totalThisWeek = totalsUSDC[week_iterator];
            if (totalThisWeek > 0) {
                // need to check lest div by 0
                // staker's share of rewards for given week
                totalReward += (reward * liquidity) / totalThisWeek;
            }
            week_iterator += 1;
            reward = weeklyRewardUSDC;
        }
        so_far = (block.timestamp - DEPLOYED) / 1 hours;
        delta = so_far - (current_week * HOURS_PER_WEEK);
        // the last reward will be a fraction of a whole week's worth
        reward = (delta * weeklyRewardUSDC) / HOURS_PER_WEEK; 
        // because we're in the middle of a current week
        totalReward += (reward * liquidity) / liquidityUSDC;
        // update when rewards were collected for this tokenId 
    }
    
    // provide a tokenId if beneficiary already has an NFT
    // otherwise, an NFT deposit will be created for the corresponding pool
    // targetting the full price range
    function deposit(address beneficiary, uint amount, 
    address token, uint tokenId) external payable {
        require(!PAUSED, "Marenate::deposit: contract paused");
        amount = _min(amount, IERC20(token).balanceOf(msg.sender));
        uint amount1 = token == QUID ? amount : 0;
        uint amount0 = token == USDC ? amount : 0;
        require(amount1 + amount0 > 0, "Marenate::deposit: bad token");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(NFPM, amount);
        if (tokenId != 0) {
            uint timestamp = depositTimestamps[beneficiary][tokenId];
            require(timestamp > 0, "Marenate::deposit: tokenId doesn't exist");
            (,, address token0,,
             ,,, uint128 liquidity,,,,) = INonfungiblePositionManager(NFPM).positions(tokenId);
            uint current_week = _roll();
            uint reward = _reward(timestamp, liquidity, 
                                  token0, current_week);
            liquidityUSDC -= liquidity;
            liquidity = _collect(tokenId, address(this), 
                                 amount0 + reward, amount1);
            liquidityUSDC += liquidity;
            depositTimestamps[msg.sender][tokenId] = block.timestamp;
        } else {
            INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: USDC, token1: QUID,
                fee: FEE_USDC,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0, amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });
            (uint tokenID, uint128 liquidity,,) = INonfungiblePositionManager(NFPM).mint(params);
            depositTimestamps[beneficiary][tokenID] = block.timestamp;
            NFT memory nft; nft.id = tokenID;
            usdcIDs[beneficiary].push(nft);
            liquidityUSDC += liquidity;
            require(liquidity >= minLiquidity, 
            "Marenate::deposit: minLiquidity");
        }
        require(liquidityUSDC <= maxTotalUSDC, 
                "Marenate::deposit: exceed max");
    }

    function depositNFT(uint tokenId, address from) external {
        (,, address token0, address token1,
         ,,, uint128 liquidity,,,,) = INonfungiblePositionManager(NFPM).positions(tokenId);
        require(token1 == QUID && token0 == USDC, "Marenate::deposit: improper token id");
        // usually this means that the owner of the position already closed it
        require(liquidity > 0, "Marenate::deposit: cannot deposit empty amount");
        
        NFT memory nft;
        nft.id = tokenId;
        nft.burned = false;
        
        require(usdcIDs[from].length < 22, 
            "Marenate::deposit: exceeding max");
        
        usdcIDs[from].push(nft);
        totalsUSDC[_roll()] += liquidity;
        
        liquidityUSDC += liquidity;
        require(liquidityUSDC <= maxTotalUSDC, 
        "Marenate::deposit: over max liquidity");
        
        depositTimestamps[from][tokenId] = block.timestamp;
        // transfer ownership of LP share to this contract
        INonfungiblePositionManager(NFPM).transferFrom(msg.sender, address(this), tokenId);
        emit DepositNFT(tokenId, msg.sender);
    }
}
