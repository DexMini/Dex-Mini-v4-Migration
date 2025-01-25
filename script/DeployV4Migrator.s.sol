// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DexMiniV4Migrator} from "../src/Dexminiv4Migrator.sol";
import {IV3PositionManager} from "../src/interfaces/IV3PositionManager.sol";
import {IV4PoolManager} from "../src/interfaces/IV4PoolManager.sol";
import {IV4Vault} from "../src/interfaces/IV4Vault.sol";

contract DeployDexMiniV4Migrator is Script {
    // Base Sepolia addresses
    address constant V3_POSITION_MANAGER = 0x1238536071E1c677A632429e3655c799b22cDA52; // Base Sepolia V3 NonfungiblePositionManager
    
    // These addresses will need to be updated once V4 is deployed
    address constant V4_POOL_MANAGER = 0x93C331265cAa5f84DD25Fb93Fc04f0A00aAA9c22; // Base Sepolia V4 PoolManager
    address constant V4_VAULT = 0x5A90749487b7C2f4748dA5d7A7F009c927c2ce50;        // Base Sepolia V4 Vault

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy V4Migrator
        DexMiniV4Migrator migrator = new DexMiniV4Migrator(
            IV3PositionManager(V3_POSITION_MANAGER),
            IV4PoolManager(V4_POOL_MANAGER),
            IV4Vault(V4_VAULT)
        );

        vm.stopBroadcast();

        // Log deployment information
        console.log("DexMiniV4Migrator deployed to:", address(migrator));
        console.log("Configuration:");
        console.log("- V3 Position Manager:", V3_POSITION_MANAGER);
        console.log("- V4 Pool Manager:", V4_POOL_MANAGER);
        console.log("- V4 Vault:", V4_VAULT);
    }
} 