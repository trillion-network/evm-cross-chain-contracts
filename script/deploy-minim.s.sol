pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TokenMessengerMinim.sol";

contract DeployMinimScript is Script {
    uint256 private tokenMessengerDeployerPrivateKey;

    /**
     * @notice deploys TokenMessenger
     * @param privateKey Private Key for signing the transactions
     * @return TokenMessenger instance
     */
    function deployTokenMessenger(
        uint256 privateKey
    ) private returns (TokenMessengerMinim) {
        // Start recording transations
        vm.startBroadcast(privateKey);

        // Deploy TokenMessenger
        TokenMessengerMinim tokenMessengerMinim = new TokenMessengerMinim();

        // Stop recording transations
        vm.stopBroadcast();

        return tokenMessengerMinim;
    }

    /**
     * @notice initialize variables from environment
     */
    function setUp() public {
        tokenMessengerDeployerPrivateKey = vm.envUint(
            "TOKEN_MESSENGER_DEPLOYER_KEY"
        );
    }

    /**
     * @notice main function that will be run by forge
     */
    function run() public {
        // Deploy TokenMessengerMinim
        TokenMessengerMinim tokenMessenger = deployTokenMessenger(
            tokenMessengerDeployerPrivateKey
        );
        console.logAddress(address(tokenMessenger));
    }
}
