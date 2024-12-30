## Trillion EVM cross chain contract

Foundry-based repo for Trillion smart contracts.

## Usage

### Install solc v0.8.28
```shell
solc-select use 0.8.28 --always-install
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

Example of how to deploy a simple contract using a Foundry script.

```shell
forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

To deploy `TokenMessenger` `TokenBurner` `NonceMAnager` with a private key, enter the required env vars in `.env`, then run:

```shell
npm run deploy:sepolia
npm run deploy:sepolia:broadcast
npm run deploy:optimismSepolia
npm run deploy:optimismSepolia:broadcast
```
broadcast is to execute the transaction

To deploy with hardware wallet:

```shell
forge script DeployScript --verify --ffi -vvvv --broadcast --ledger --sender $HARDWARE_WALLET_ADDRESS --sig \"run(string)\" sepolia
```


### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
