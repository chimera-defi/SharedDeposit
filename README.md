# SharedDeposit

# Deployed mainnet contracts

// Aug 31 '21
NFT
MintableNFTSale deployed to 0x926a65012C23dcfB2227af46e6135C1c6413D8Ac at https://etherscan.io/address/0x926a65012C23dcfB2227af46e6135C1c6413D8Ac
cost: 322125589811035895 or 0.322 ETH

founderVesting deployed to 0x0279eBC54179EBc5E5e65A9f036Db351233adDc6 at https://etherscan.io/address/0x0279eBC54179EBc5E5e65A9f036Db351233adDc6  
treasuryVesting deployed to 0x2Cb4bdc030975f2ABdbbb984e87715505C51D5BC at https://etherscan.io/address/0x2Cb4bdc030975f2ABdbbb984e87715505C51D5BC  
SGTv2 deployed to 0x24C19F7101c1731b85F1127EaA0407732E36EcDD at https://etherscan.io/address/0x24C19F7101c1731b85F1127EaA0407732E36EcDD

TokenMigrator deployed to 0x9615460582Efa2a9b1d8D21e7E02afE43A415E13 at https://etherscan.io/address/0x9615460582Efa2a9b1d8D21e7E02afE43A415E13  
VoteEscrowFactory deployed to 0xeE5bd4b9C875BE3958b1255D181B8B3E978903b9 at https://etherscan.io/address/0xeE5bd4b9C875BE3958b1255D181B8B3E978903b9  
SimpleTimelock deployed to 0xC0AAB794F9D2aA7cE56B8BEB6cFfc71BC05c21FC at https://etherscan.io/address/0xC0AAB794F9D2aA7cE56B8BEB6cFfc71BC05c21FC  
FundDistributor deployed to 0x38aa4CC003D9Ad84505bc7b096122402Db31f708 at https://etherscan.io/address/0x38aa4CC003D9Ad84505bc7b096122402Db31f708  
MasterChef deployed to 0x84B7644095d9a8BFDD2e5bfD8e41740bc1f4f412 at https://etherscan.io/address/0x84B7644095d9a8BFDD2e5bfD8e41740bc1f4f412

VeSGT : 0x21b555305e9d65c8b8ae232e60fd806edc9c5d78 : https://etherscan.io/address/0x21b555305e9d65c8b8ae232e60fd806edc9c5d78#code

# Goerli

May 24 '22
Goerli test of streamlined Withdrawals contract
/// @dev Test on goerli deployed at https://goerli.etherscan.io/address/0x4db116ad5cca33ba5d2956dba80d56f27b6b2455

# Quickstart and developer notes

- Following env best practices from https://github.com/paulrberg/solidity-template
- Pre-run checks:

```
npm i --force
yarn sol
```

# Errors

A note on errors
To reduce bytecode size and gas costs, error strings are shortened following UNIv3 as an example.  
The template is: {origin contract}:reason  
Common reasons:

```
CBL0 - contract balance will be less than 0 after this operation
VL0 - Value less than or equal to 0 and needs to be greater than 0
VLC - Value less than cap or check amount
AGC - Amount greater than cap or some stored value or requirement
NA - No Access / Not allowed
AE - Already exists
0AD - 0 address
```

# SharedDeposit V2

Spec:

- TODO

# SharedDeposit V3

Spec:

- Use CLI options to set ETH1 exit as this upgradeable contract - contract needs to be upgradeable
- This allows trustless staking as ETH cannot to be taken by an admin
- Disable any future migrations or minting and control minting roles
- Build a large broader community multisig with partners and set it as owner of the contract
- Require a withdrawal queue to prevent bot arbitrage
- Create a oracle for single token value tracking for VETH2 price appreciation that can be updated with offchain calc on validators
- Bonus:
- Auto buy SGT from generated fees and send to master chef type contracts for rewards boost
- Require the user to have some SGT for solo staking or withdrawing VETH2 into ETH at a discounted market rate
- Allow the contract to be deployed via a factory allowing others to reuse the scaffolding to create their own ETH2 staking solutions i.e. staking server providers such as certus one
- Minting support to allow adding a new minter to support swapping a share token into a yield bearing sharing token controlled by the oracle module
  e.g. swapping veth2 to a yield bearing eth2 validator share derivative token
- Support for stable coins
- Address blocklist; currently deploying a new eth2 validator takes effort. one can assume exiting one would also take effort. a blocklist would prevent a malicious address from forcing continous entries and exits e.g. an address adding and exiting 1000s of eth every epoch. some parameters should be set to prevent user concers such as a final exit allowance

# Gas profiling

Gas profiling on goerli with different optimizations.  
Transfer costs:  
Optimizations | Cost
5000000 | 51481
200 | 51553

This represents a 0.13% improvement in the cost of a transfer, arguably the most frequent interaction.  
Deploy costs:  
Optimizations | Cost  
5000000 | 27645256739592190  
200 | 22124896691748864

This represents a 24% increase in deployment costs with 5000000 optimizer runs vs 200.

This was carried out on Goerli using a gas price avg of 4.5 Gwei.  
Based on this a 200 run base is chosen.

Gas costs of large lists in args:  
With around ~100 addresses in a constructor arg gas price of the entire deploy stack increased by around 10%.

Added gas observations - may '23

- OZ methods are not always optimal / most effecient. e.g. see address.sendValue vs examples from solidity docs to achieve same
- 30% call cost reduction for 2% more contract size
  Optimization increases deployment of withdrawals.sol by 10k gas units, but shows a call cost reduction of 3k / call or ~3% on empty loops i.e redeem without any staked collateral
- loading calldata into mem e.g. via `address usr = msg.sender;` vs loading directly from msg.sender where needed
- setting global vars to immutable

# Deploying gov v2 to prod

- First we build to lint everything and make sure everything is standard
- Then clean to prevent etherscan verify issues
- Then we run the deploy gov script which will deploy main contracts and allocate specific funding to them all. This script will also then run etherscan verify
- **Manual followups are needed**
- Create a Sushiswap LP position
- Create a vote escrow token for these lP positions using the vote escrow factory
- Add these LP tokens and vote escrow tokens to the masterchef contract
- Set burn address for the vote escrow contract to 0x..dead
- Make sure vote escrow contract works
- Make sure farming master chef contract works
- Burn initial LP tokens manually or via unicrypt

```
npm run-script deploy_gov_prod
```

# Extended Deploy logs Sep 1 2021

```
Deployed SGTv2 to 0x24C19F7101c1731b85F1127EaA0407732E36EcDD on mainnet

Deployed TokenMigrator to 0x9615460582Efa2a9b1d8D21e7E02afE43A415E13 on mainnet

Deployed VoteEscrowFactory to 0xeE5bd4b9C875BE3958b1255D181B8B3E978903b9 on mainnet

Deployed SimpleVesting to 0x0279eBC54179EBc5E5e65A9f036Db351233adDc6 on mainnet

Deployed SimpleVesting to 0x2Cb4bdc030975f2ABdbbb984e87715505C51D5BC on mainnet

Deployed SimpleTimelock to 0xC0AAB794F9D2aA7cE56B8BEB6cFfc71BC05c21FC on mainnet

Deployed FundDistributor to 0x38aa4CC003D9Ad84505bc7b096122402Db31f708 on mainnet
Initialized FundDistributor with 0x24C19F7101c1731b85F1127EaA0407732E36EcDD

Tokens transferred: From 0x24C19F7101c1731b85F1127EaA0407732E36EcDD to TokenMigrator at 0x9615460582Efa2a9b1d8D21e7E02afE43A415E13 : 3200000000000000000000000
Tokens transferred: From 0x24C19F7101c1731b85F1127EaA0407732E36EcDD to treasuryVesting at 0x2Cb4bdc030975f2ABdbbb984e87715505C51D5BC : 2380000000000000000000000
Tokens transferred: From 0x24C19F7101c1731b85F1127EaA0407732E36EcDD to founderVesting at 0x0279eBC54179EBc5E5e65A9f036Db351233adDc6 : 1020000000000000000000000
Tokens transferred: From 0x24C19F7101c1731b85F1127EaA0407732E36EcDD to FundDistributor at 0x38aa4CC003D9Ad84505bc7b096122402Db31f708 : 2040000000000000000000000
Tokens transferred: From 0x24C19F7101c1731b85F1127EaA0407732E36EcDD to SimpleTimelock at 0xC0AAB794F9D2aA7cE56B8BEB6cFfc71BC05c21FC : 1360000000000000000000000
Setup farming
Granting ACL rights to 0xcB9D78CB76a86844667eAF3Ac62CB5D377b3ce5C
Granting ACL rights to 0x610c92c70Eb55dFeAFe8970513D13771Da79f2e0
Granting ACL rights to 0xa1feaF41d843d53d0F6bEd86a8cF592cE21C409e
ACL Sentinels added
Ownership transferred for treasuryVesting at 0x2Cb4bdc030975f2ABdbbb984e87715505C51D5BC to 0xeBc37F4c20C7F8336E81fB3aDf82f6372BEf777E
Ownership transferred for SimpleTimelock at 0xC0AAB794F9D2aA7cE56B8BEB6cFfc71BC05c21FC to 0xeBc37F4c20C7F8336E81fB3aDf82f6372BEf777E
Ownership transferred for FundDistributor at 0x38aa4CC003D9Ad84505bc7b096122402Db31f708 to 0xeBc37F4c20C7F8336E81fB3aDf82f6372BEf777E
Ownership transferred for TokenMigrator at 0x9615460582Efa2a9b1d8D21e7E02afE43A415E13 to 0xeBc37F4c20C7F8336E81fB3aDf82f6372BEf777E
Ownership transferred for Blocklist at <redacted> to 0xeBc37F4c20C7F8336E81fB3aDf82f6372BEf777E
Ownership transferred for Allowlist at <redacted> to 0xeBc37F4c20C7F8336E81fB3aDf82f6372BEf777E
```
