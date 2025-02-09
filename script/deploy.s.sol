// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";

import {TokenBurner} from "../src/TokenBurner.sol";
import {TokenMessenger} from "../src/TokenMessenger.sol";

contract DeployScript is Script {
    address private tokenContractAddress;
    address private tokenRemoteContractAddress;
    address private controllerAddress;
    address private pauserAddress;
    address private rescuerAddress;

    uint32 private remoteDomain;
    uint256 private burnLimitPerMessage;
    uint256 private deployerPrivateKey;

    /**
     * @notice deploys TokenMessenger
     * @param privateKey Private Key for signing the transactions
     * @return TokenMessenger instance
     */
    function deployTokenMessenger(uint256 privateKey) private returns (TokenMessenger) {
        // Start recording transations
        vm.startBroadcast(privateKey);

        // Deploy TokenMessenger
        TokenMessenger tokenMessenger = new TokenMessenger();

        // Add Rescuer
        tokenMessenger.updateRescuer(rescuerAddress);

        // Stop recording transations
        vm.stopBroadcast();

        return tokenMessenger;
    }

    /**
     * @notice deploys TokenBurner
     * @param privateKey Private Key for signing the transactions
     * @param tokenMessengerAddress TokenMessenger Contract address
     * @return TokenBurner instance
     */
    function deployTokenBurner(uint256 privateKey, address tokenMessengerAddress) private returns (TokenBurner) {
        // Start recording transations
        vm.startBroadcast(privateKey);

        // Deploy TokenBurner
        TokenBurner tokenBurner = new TokenBurner(controllerAddress);

        // Add Local TokenMessenger
        tokenBurner.addLocalTokenMessenger(tokenMessengerAddress);

        // Add Pauser
        tokenBurner.updatePauser(pauserAddress);

        // Add Rescuer
        tokenBurner.updateRescuer(rescuerAddress);

        // Stop recording transations
        vm.stopBroadcast();

        return tokenBurner;
    }

    /**
     * @notice add local burner to the TokenMessenger
     */
    function addBurnerAddressToTokenMessenger(TokenMessenger tokenMessenger, uint256 privateKey, address burnerAddress)
        private
    {
        // Start recording transations
        vm.startBroadcast(privateKey);

        tokenMessenger.addLocalBurner(burnerAddress);

        // Stop recording transations
        vm.stopBroadcast();
    }

    /**
     * @notice link current chain and remote chain tokens
     */
    function linkTokenPair(TokenBurner tokenBurner, uint256 privateKey) private {
        // Start recording transations
        vm.startBroadcast(privateKey);

        tokenBurner.setMaxBurnAmountPerMessage(tokenContractAddress, burnLimitPerMessage);

        // Stop recording transations
        vm.stopBroadcast();
    }

    /**
     * @notice initialize variables from environment
     */
    function setUp() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        controllerAddress = vm.envAddress("CONTROLLER_ADDRESS");
        pauserAddress = vm.envAddress("PAUSER_ADDRESS");
        rescuerAddress = vm.envAddress("RESCUER_ADDRESS");
        tokenContractAddress = vm.envAddress("TOKEN_CONTRACT_ADDRESS");
        burnLimitPerMessage = vm.envUint("BURN_LIMIT_PER_MESSAGE");
        remoteDomain = uint32(vm.envUint("REMOTE_DOMAIN"));
    }

    /**
     * @notice main function that will be run by forge
     */
    function run(string memory chain) public {
        vm.createSelectFork(vm.rpcUrl(chain));

        // Deploy TokenMessenger
        TokenMessenger tokenMessenger = deployTokenMessenger(deployerPrivateKey);

        // Deploy TokenBurner
        TokenBurner tokenBurner = deployTokenBurner(deployerPrivateKey, address(tokenMessenger));

        // Add Local Minter
        addBurnerAddressToTokenMessenger(tokenMessenger, deployerPrivateKey, address(tokenBurner));

        // Link token pair and add remote token messenger
        linkTokenPair(tokenBurner, deployerPrivateKey);
    }
}
