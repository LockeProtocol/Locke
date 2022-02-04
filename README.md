
This repo consists of 5 main contracts:
| Contract Name    | Description      | SLOC |
| ---------------- | ---------------- | ---- |
| `StreamFactory`  | A factory for creating `Streams`                                             | \~600 |
| `Stream`         | A contract for managing 2 counterparty token lockup rental & buying          | \~800 |
| `MerkleStream`   | Same as Stream, but with merkle tree restrictions for staking                | \~70 |
| `LockeERC20`     | Inherited by `Stream`, this turns `Stream` deposits into a transferable ERC20| \~200 |
| `Gov`            | Extremely minimal governance                                                 | \~50 |


### Testing

```bash
git clone --recurse https://github.com/LockeProtocol/Locke
```

Download & install [`forge`](https://github.com/gakonst/foundry).

`forge test -vvv` to run all tests.


## Contract Overview
### `StreamFactory`

This contract is a factory that generates `Streams`. It has 7 governable parameters. The only limitation should be on `feePercent` which should not exceed 5%.
<div style="page-break-after: always; break-after: page;"></div>

The main entry is for DAOs to call `createStream`, passing in a token they are going to be rewarding depositors (the `rewardToken`), the deposit token, the start time of the stream, how long the stream lasts, how long deposits are locked for _after_ the end of the stream, and how long rewards are locked _after_ the end of the stream.
<div style="page-break-after: always; break-after: page;"></div>

Calling the function should deploy a new contract with a unique id and pass in the factory's fee parameters + the creator's parameters.
<div style="page-break-after: always; break-after: page;"></div>

Updating of stream limits + fee limits are only accessible to the `governor` of the contract. This governorship is updateable in a 2 step process.


### `Stream`
#### Lifecycle
A stream is created by a stream creator. This initializes a bunch of immutable values, mostly to do with the lifetime of the contract. The lifetime can be broken down as follows:
1. Creation
2. Funding + Staking period
3. Stream + Staking period
4. Deposit Locked period
5. Claiming period
<div style="page-break-after: always; break-after: page;"></div>

The lifetimes are defined by the following variables
<div style="page-break-after: always; break-after: page;"></div>

`Creation`: self explanatory
<div style="page-break-after: always; break-after: page;"></div>

`Funding + Staking`: creation thru `startTime`
<div style="page-break-after: always; break-after: page;"></div>

`Streaming + Staking`: `startTime` thru `startTime + streamDuration` (`endStream`)
<div style="page-break-after: always; break-after: page;"></div>

`Deposit Locked`: `endStream` thru `endDepositLock`
<div style="page-break-after: always; break-after: page;"></div>


`Claiming`: for rewards `endRewardLock`, for deposits `endDepositLock` thru infinity (technically to `block.timestamp = 2**32`)
<div style="page-break-after: always; break-after: page;"></div>

##### Creation
Creation is just the construction of the contract. It sets a bunch of immutables mostly to do with lifecylce timing, fees, and tokens. Of note, there is a `isIndefinite`, which denotes that the depositors *are locking up their deposit tokens indefinitely* for the _rewardToken_. The stream creator then has control over these `depositTokens`.
<div style="page-break-after: always; break-after: page;"></div>

##### Funding + Staking Period
Once a contract is created, it is ready to be funded by _anyone_, via the `fundStream` function. This function should support any ERC20 as the `rewardToken` besides rebasing tokens which is explicitly out of scope. Fee on transfer tokens and no-return ERC20s are in scope. Additionally, ERC20s whose balance may go above `type(uint112).max` are unsupported, similar to uniswap V2.
<div style="page-break-after: always; break-after: page;"></div>

Additionally, if the `StreamFactory` had fees enabled, the governor of the factory contract should be able to collect the fees which should be a percentage of the `rewardToken`s used to fund the stream.
<div style="page-break-after: always; break-after: page;"></div>

During this time, user can also deposit their `depositTokens`, via the `stake` function. The stream hasn't started yet so no rewards should stream to them yet though. Additionally, the user should be able to withdraw their entire balance via the `exit` function prior to the stream starting, or specify an amount of `depositTokens` to withdraw via the `withdraw` function.
<div style="page-break-after: always; break-after: page;"></div>

##### Stream + Staking period
Once a stream has started, `depositTokens` become linearly locked until `endDepositLock` (unless it is indefinite, in which case they are claimable by the stream creator).
<div style="page-break-after: always; break-after: page;"></div>

For example, if you deposit 100 USDC before `startTime`, as soon as the clock passes `startTime`, tokens should become locked linearly over the `streamDuration`. So if the stream duration is 100 seconds, each second, 1 USDC would be locked until `endDepositLock`.
<div style="page-break-after: always; break-after: page;"></div>

What the depositor gets in return is a continuous stream of `rewardTokens` until `endStream`. The amount of `rewardTokens` should be equivalent to each depositors % of the unstreamed amounts becoming locked. So if you represent 20% of the tokens being streamed, you should earn 20% of the reward tokens _while your tokens represent that 20%_. If the % changes, your reward should change as well, while maintaining the previous rewards. This is basically like other Synthetix Rewards contract, with the added caveat that your actual balance _decreases_ over time as tokens become locked. To work around this, we use `virtualBalances`, which takes into account how much of the remaining `rewardTokens` can you fight to earn. This is detailed in the `dilutedBalance` function.
<div style="page-break-after: always; break-after: page;"></div>

Withdrawing during this timeperiod has some caveats as well, as some of your tokens will have already been locked. So we must keep track of the remaining unlocked tokens that are still available to withdraw (`TokenStream.tokens`).
<div style="page-break-after: always; break-after: page;"></div>

There is a helper `exit` function that just withdraws your remaining balance.
<div style="page-break-after: always; break-after: page;"></div>

Additionally, there is an ERC20 minted (if its not indefinite), that represents your deposit into the protocol. This becomes transferable afterward and will be needed to reclaim your deposit tokens after `endDepositLock`.
<div style="page-break-after: always; break-after: page;"></div>

##### Deposit Locked period
At this point, all deposit tokens should be locked and the receipt tokens minted should be transferable. Once the `streamDuration` has elapsed, if `isSale`, the creator can withdraw the deposit tokens & the governor can withdraw any `fees`. Otherwise, the contract lays dormant. At any point in any of the time periods, flashloaning (of `depositToken` or `rewardToken` only) and arbitrary calls (to contracts != `depositToken` || `rewardToken`) can be performed by anyone and governance respectively.


<div style="page-break-after: always; break-after: page;"></div>

##### Claiming period
After `endDepositLock`, deposits can be reclaimed by burning the receipt tokens received from depositing. After `endRewardLock`, any earned rewards should be claimable via `claimReward` function.
<div style="page-break-after: always; break-after: page;"></div>



### Math

<google-sheets-html-origin><!--td {border: 1px solid #ccc;}br {mso-data-placement:same-cell;}-->

#### Real deposits + withdraws

_ | start of Day 0 | start of Day 1 | start of Day 2 | start of Day 3 | start of Day 4 | start of Day 5 | start of Day 6 | start of Day 7 | start of Day 8 | start of Day 9 | start of Day 10
-- | --             | --             | --             | --             | --             | --             | --             | --             | --             | --             | --
Alice | $100.00 |   |   |   |   |   | -$40.00 |   |   |   |
Bob |   |   |   |   |   |   |   |   |   |   |
Charlie |   |   |   |   |   | $100.00 |   |   |   |   |


#### Dilution factor
<google-sheets-html-origin><!--td {border: 1px solid #ccc;}br {mso-data-placement:same-cell;}-->

title | start of Day 0 | start of Day 1 | start of Day 2 | start of Day 3 | start of Day 4 | start of Day 5 | start of Day 6 | start of Day 7 | start of Day 8 | start of Day 9 | start of Day 10
-- |-- | -- | -- | -- | -- | -- | -- | -- | -- | -- | --
dilution_factor | 1 | 1.111111111 | 1.25 | 1.428571429 | 1.666666667 | 2 | 2.5 | 3.333333333 | 5 | 10 | #DIV/0!

#### Balance over time
<google-sheets-html-origin><!--td {border: 1px solid #ccc;}br {mso-data-placement:same-cell;}-->

name | start of Day 0 | start of Day 1 | start of Day 2 | start of Day 3 | start of Day 4 | start of Day 5 | start of Day 6 | start of Day 7 | start of Day 8 | start of Day 9 | start of Day 10
-- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | --
Alice's unstreamed | $100.00 | $90.00 | $80.00 | $70.00 | $60.00 | $50.00 | $40.00 | $0.00 | $0.00 | $0.00 | $0.00
Bob's unstreamed |   | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00
Charlie's unstreamed | 0 | $0.00 | $0.00 | $0.00 | $0.00 | $100.00 | $80.00 | $60.00 | $40.00 | $20.00 | $0.00



#### Virtual Balances
<google-sheets-html-origin><!--td {border: 1px solid #ccc;}br {mso-data-placement:same-cell;}-->

name |start of Day 0 | start of Day 1 | start of Day 2 | start of Day 3 | start of Day 4 | start of Day 5 | start of Day 6 | start of Day 7 | start of Day 8 | start of Day 9 | start of Day 10
-- |-- | -- | -- | -- | -- | -- | -- | -- | -- | -- | --
Alice | $100.00 | $100.00 | $100.00 | $100.00 | $100.00 | $100.00 | $0.00 | $0.00 | $0.00 | $0.00 | #DIV/0!
Bob | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | #DIV/0!
Charlie | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 | $200.00 | $200.00 | $200.00 | $200.00 | $200.00 | #DIV/0!

In this example, we can see that Alice *only* has $40 to withdraw at the start of day 6, because thats all that is left unstreamed. the other $60 is locked until `endDepositLock`. `40 * 2.5 == 100 virtual balance`.