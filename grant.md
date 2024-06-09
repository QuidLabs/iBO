## UNISWAP-ARBITRUM GRANT 

### Project Overview: fair-launched memecoin as a stable(ish) Future $

Maker & [Spark](https://x.com/StaniKulechov/status/1711765177505353852) account for 57% of  ETH TVL (incl. LSTs) between all lending markets.    
[Derivatives](https://twitter.com/lex_node/status/1740509787690086847) derive their value from an underlying asset. Our ~~certicificate of deposit~~...   
[capital deepening](https://www.wallstreetmojo.com/capital-deepening/) token (QD) derives its value from stable collateral used to `mint`;  
It takes 1 year for minted QD tokens to mature, after this they become redeemable. 

- Arbitrum Launch: June 27th
- User Adoption (2024-'25): 35.7M in  
QD minted for Q2 (same within Q4) as   
the minimum target (10x for reach goal) 
     
- Contract Interaction: facilitate at least 46  
  `Plunge` positions, inviting 10 more each.

- Partnerships: Milestone 2 and onwards  

**Request for Proposal (RFP)**: New Protocols   
for Liquidity Management and *"Derivatives"*

**Proposer**: QuidMint Foundation   
**Requested funds**: 100 000 ARB   
**Payment address**: `quid.eth`    

Arbitrum's chainId starts with  
42, public keys are 42 symbols...  
`quid.eth`'s starts with 42; ends  
with 4A4, so we built gilts as  
a sort of simplified ERC404:   

replaced 0 with A..."the secret  
to survivin'...is knowin' what to   
throw away, and knowin' what    
to keep..." on commodifying...  

- **Launch Costs:** 100 000 ARB
  - **Legal costs:** 42 000 per year
    - Solidity [audit]() + general  
    counsel retainer: 31 000  
    [Cayman](https://arbiscan.io/tx/0x5e4b70fad2039257bfe742d42a0fe085525351b99f1f979c424ddf93a60c882a): 11k + late fees
  - **Quid Labs:** 31 000 USD bi-monthly
    - **Full-Time Development**: 
      - Senior React developer
      - Senior Solidity developer 
    - **Part-Time Research**: 
      - Econometric 
      - UX Designer
  
- **Incentivised beta group (27 Club):** 27 000 ARB 
  - 46 `Plunge`s ($600 per)
  - Prove quality of the audit

### Milestone 1 (May-July '24): preparation

QU!D is a decentralized liquidity aggregation protocol  
built on top of multiple blockchain software stacks...   
(go-to-market version is in Solidity): to arrive at its  
current codebase, Quid Labs had to rebuild 3 times.  

Majority of the work for this milestone has been devoted to testing  
this implementation,  extending  `frontend` functionality for all 8  
 
Contract functions in `Moulinette.sol` powering the in-house  
[tokenomics](https://jumpcrypto.com/writing/token-design-for-serious-people/), and `Marenate.sol` (which integrates UNI and LINK).

| Number | Deliverable | Specification |
| -----: | ----------- | ------------- |
| 0.| License | GPLv3 Copyleft is the technique of granting freedoms over copies  with  the requirement that the same rights be preserved in *derivative* works. |
| 1. | `call` widget | ETH which was deposited into `carry` may be freely  withdrawn. QD redemption (for sDAI/sFRAX/sUSDe) depends when QD was minted. `call` means to call out, but also to `call` in, this will interact with Arbitrum's bridge contracts, and use an external backend  |
| 2. | Vertical fader | All the way down by default, there should be one input slider for the magnitude of either long leverage (or short), and a toggle to switch between the two directions (including a toggle for `flip`: 2x multiplier for APR).|
| 3a. | Cross-fader for balance | This slider will represent how much of the user’s total QD is at risk (deposited in `work`), and the % in `carry` (by default 100% balance left in `carry`).|
| 3b. | Cross-faders for voting | Shorts and longs are treated as separate risk budgets, so there is one APR target for each (combining them could be a worthy experiment, definitely better UX, though not necessarily optimal from an analytical standpoint).  |
| 4. | Basic Metrics |  Provide a side by side comparison of key metrics: aggregated for all users, and from the perspective of the authenticated user (who’s currently logged in); most recently liquidated (sorted by time or size); top borrowers' P&L. |
| 5. | Simulation [Metrics](https://orus.info/) | Future projections for the possible outputs of the `call` function, with variable inputs being: the extent to which `work` is leveraged relative to `carry` over time; % and size of profitable `fold`s over the last SEMESTER.  |

### Milestone 2 (July-Sep): initial sub-domain and other domains
  
As part of the 1st milestone , `yo.quid.io` will be the first external operator (QU!D Ltd in BVI) running `frontend` (stand-a-loan web app  for 8 contract functions, visualising stats).  

| Number | Deliverable | Specification |
| -----: | ----------- | ------------- |
| 1. | Off-chain Watcher for on-chain events (liquidation script) | Publish codebase for reading opportunities to liquidate, so anyone can trigger `clocked`. Later, this code could be potentially integrated with ZigZag's off-chain order matcher for making QU!D order-book-friendly. |
| 2. | [Twitter spaces](https://t.ly/B7pin) | Announce partnerships, and demonstrate the extent of readiness of the frontend by interacting with all protocol functions (minting is the only thing that may be done for the first 46 days after deployment). |
| 3. | Linking multiple protocol deployments | Trading QD 1:1 against other tokens using the same protocol (potentially on multiple EVMs with domain-specific adjustments). As part of the protocol brand, we will borrow one more feature from ERC404: ownership of a custom-faced dollar bill NFT (provided a minimum 1k balance). |
| 4. |  Profile Preferences and Push Notifications| Advancing on frontend progress from milestone 1, users should have the ability to pull custom insights into their trading dashboard to better inform decisions. For example, over-bought / over-sold signaling involves a [handful of TA indicators](https://github.com/QuidLabs/bnbot/blob/main/Bot.py#L366). |
