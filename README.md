# SharedDeposit

- Following env best practices from https://github.com/paulrberg/solidity-template
- Pre-run checks:

```
npm run-script prettier
npm run-script lint:sol
npx hardhat compile
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
