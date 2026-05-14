// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ProposalRegistry} from "../../contracts/solidity/ProposalRegistry.sol";
import {TreasuryVault} from "../../contracts/solidity/TreasuryVault.sol";
import {TaxEngine} from "../../contracts/solidity/TaxEngine.sol";
import {PolicyRegistry} from "../../contracts/solidity/PolicyRegistry.sol";
import {OracleAggregator} from "../../contracts/solidity/OracleAggregator.sol";
import {ERC20Adapter} from "../../contracts/solidity/adapters/ERC20Adapter.sol";
import {AaveAdapter} from "../../contracts/solidity/adapters/AaveAdapter.sol";
import {PendleAdapter} from "../../contracts/solidity/adapters/PendleAdapter.sol";
import {RobinhoodRWAAdapter} from "../../contracts/solidity/adapters/RobinhoodRWAAdapter.sol";
import {ITreasuryVault} from "../../contracts/solidity/interfaces/ITreasuryVault.sol";

/// @notice A mock ERC20 token for testnet interaction testing.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "allowance");
        require(balanceOf[from] >= amount, "insufficient");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/// @notice Comprehensive interaction script for generating rich on-chain test data.
///         Deploys mock tokens, exercises every contract function, simulates multi-role workflows.
contract InteractionSuite is Script {
    // ─── Deployed contract addresses ───
    address constant VAULT           = 0x2A46cF6493b377D45908254B0528e38990AA323f;
    address constant PROPOSAL_REG    = 0x494960e21058290BB2F1328b6b837dCF26aA5DCb;
    address constant POLICY_REG      = 0x7058132Ba4aE19983c61590644F2943A3B7fDf80;
    address constant TAX_ENGINE      = 0x8a8C3532359aAACb6C3a1060deF4938F6006c8F1;
    address constant ORACLE          = 0x6F4DF8979a8f18Ce3fD2ff941e5a3610E5cAfCa5;
    address constant ERC20_ADAPTER   = 0x77472dADA40B8c30304a7FbbAf14e1b200A5c7FE;
    address constant AAVE_ADAPTER    = 0x1D77BBE8E921604c47CAb229Fc0727C5967F19a8;
    address constant PENDLE_ADAPTER  = 0x759aE549389eeDf1F055606fD9b72d071c7Ac3fa;
    address constant RWA_ADAPTER     = 0x41d158986CDAd44c7275A681a05215c9Aa1cAe1e;

    // ─── Roles ───
    address constant GUARDIAN = 0xC7e424c1E4B346c06A35241e7BCa469477483683;
    address constant AGENT    = 0x4c9Cef3bc7F5455d2581b717f115B2c76Fc1d092;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerKey);

        console2.log("============================================");
        console2.log("  HELIX INTERACTION SUITE");
        console2.log("============================================");
        console2.log("");

        // ═══════════════════════════════════════
        // PART 1: Deploy Mock Tokens
        // ═══════════════════════════════════════
        vm.startBroadcast(deployerKey);

        console2.log("--- Part 1: Deploy Mock Tokens ---");

        MockERC20 mockUSDC = new MockERC20("Mock USDC", "mUSDC", 6);
        console2.log("MockUSDC deployed:", address(mockUSDC));

        MockERC20 mockWETH = new MockERC20("Mock WETH", "mWETH", 18);
        console2.log("MockWETH deployed:", address(mockWETH));

        MockERC20 mockARB = new MockERC20("Mock ARB", "mARB", 18);
        console2.log("MockARB deployed:", address(mockARB));

        MockERC20 mockSPY = new MockERC20("Mock tSPY", "mSPY", 18);
        console2.log("MockSPY (tokenized equity) deployed:", address(mockSPY));

        MockERC20 mockTBILL = new MockERC20("Mock T-Bill", "mTBILL", 18);
        console2.log("MockTBILL deployed:", address(mockTBILL));

        // Mint tokens to deployer
        mockUSDC.mint(deployer, 1_000_000 * 1e6);    // 1M USDC
        mockWETH.mint(deployer, 100 * 1e18);          // 100 WETH
        mockARB.mint(deployer, 500_000 * 1e18);        // 500K ARB
        mockSPY.mint(deployer, 1000 * 1e18);           // 1000 tSPY
        mockTBILL.mint(deployer, 200_000 * 1e18);      // 200K T-Bills
        console2.log("Minted tokens to deployer");

        // Also mint some to Agent for testing
        mockUSDC.mint(AGENT, 50_000 * 1e6);
        console2.log("Minted 50K mUSDC to agent");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 2: Register Mock Assets in Vault
        // ═══════════════════════════════════════
        vm.startBroadcast(deployerKey);

        console2.log("");
        console2.log("--- Part 2: Register Mock Assets ---");

        TreasuryVault vault = TreasuryVault(VAULT);

        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: address(mockUSDC),
            decimals: 6,
            isStable: true,
            isLiquid: true,
            protocol: ITreasuryVault.Protocol.WALLET,
            adapter: address(0),
            active: true
        }));
        console2.log("Registered: mUSDC");

        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: address(mockWETH),
            decimals: 18,
            isStable: false,
            isLiquid: true,
            protocol: ITreasuryVault.Protocol.WALLET,
            adapter: address(0),
            active: true
        }));
        console2.log("Registered: mWETH");

        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: address(mockARB),
            decimals: 18,
            isStable: false,
            isLiquid: true,
            protocol: ITreasuryVault.Protocol.WALLET,
            adapter: address(0),
            active: true
        }));
        console2.log("Registered: mARB");

        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: address(mockSPY),
            decimals: 18,
            isStable: false,
            isLiquid: false,
            protocol: ITreasuryVault.Protocol.RWA,
            adapter: RWA_ADAPTER,
            active: true
        }));
        console2.log("Registered: mSPY (RWA)");

        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: address(mockTBILL),
            decimals: 18,
            isStable: true,
            isLiquid: false,
            protocol: ITreasuryVault.Protocol.RWA,
            adapter: RWA_ADAPTER,
            active: true
        }));
        console2.log("Registered: mTBILL (RWA)");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 3: Deposit Tokens into Vault
        // ═══════════════════════════════════════
        vm.startBroadcast(deployerKey);

        console2.log("");
        console2.log("--- Part 3: Deposit Tokens into Vault ---");

        // Deposit 200K USDC
        mockUSDC.approve(VAULT, 200_000 * 1e6);
        vault.deposit(address(mockUSDC), 200_000 * 1e6);
        console2.log("Deposited: 200,000 mUSDC");

        // Deposit 50 WETH
        mockWETH.approve(VAULT, 50 * 1e18);
        vault.deposit(address(mockWETH), 50 * 1e18);
        console2.log("Deposited: 50 mWETH");

        // Deposit 100K ARB
        mockARB.approve(VAULT, 100_000 * 1e18);
        vault.deposit(address(mockARB), 100_000 * 1e18);
        console2.log("Deposited: 100,000 mARB");

        // Deposit 500 tSPY
        mockSPY.approve(VAULT, 500 * 1e18);
        vault.deposit(address(mockSPY), 500 * 1e18);
        console2.log("Deposited: 500 mSPY");

        // Deposit 100K T-Bills
        mockTBILL.approve(VAULT, 100_000 * 1e18);
        vault.deposit(address(mockTBILL), 100_000 * 1e18);
        console2.log("Deposited: 100,000 mTBILL");

        // Second deposit round (different amounts)
        mockUSDC.approve(VAULT, 100_000 * 1e6);
        vault.deposit(address(mockUSDC), 100_000 * 1e6);
        console2.log("Deposited: 100,000 mUSDC (2nd round)");

        mockWETH.approve(VAULT, 10 * 1e18);
        vault.deposit(address(mockWETH), 10 * 1e18);
        console2.log("Deposited: 10 mWETH (2nd round)");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 4: TaxEngine Configuration
        // ═══════════════════════════════════════
        vm.startBroadcast(deployerKey);

        console2.log("");
        console2.log("--- Part 4: TaxEngine Configuration ---");

        TaxEngine tax = TaxEngine(TAX_ENGINE);

        // Cycle through all lot methods
        tax.setLotMethod(1); // LIFO
        console2.log("Set lot method: LIFO");

        tax.setLotMethod(2); // HIFO
        console2.log("Set lot method: HIFO");

        tax.setLotMethod(0); // back to FIFO
        console2.log("Set lot method: FIFO (final)");

        // Change jurisdiction
        tax.setJurisdiction(bytes8(uint64(0x4742))); // GB
        console2.log("Set jurisdiction: GB");

        tax.setJurisdiction(bytes8(uint64(0x5347))); // SG
        console2.log("Set jurisdiction: SG");

        tax.setJurisdiction(bytes8(uint64(0x5553))); // US (back)
        console2.log("Set jurisdiction: US (final)");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 5: PolicyRegistry - Multiple Proposals
        // ═══════════════════════════════════════
        vm.startBroadcast(deployerKey);

        console2.log("");
        console2.log("--- Part 5: PolicyRegistry - Multiple Policy Proposals ---");

        PolicyRegistry policyReg = PolicyRegistry(POLICY_REG);
        bytes32[] memory noConstraints = new bytes32[](0);

        // Propose conservative policy
        bytes memory conservativePolicy = abi.encode(
            "conservative-v1",
            uint256(50), // 50% stables
            uint256(30), // 30% DeFi yield
            uint256(20)  // 20% RWA
        );
        policyReg.proposeUpdate(conservativePolicy, noConstraints);
        console2.log("Proposed: conservative-v1 policy");
        console2.log("  Pending hash:", vm.toString(policyReg.pendingPolicyHash()));

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 6: ProposalRegistry - Agent Bond Ops
        // ═══════════════════════════════════════
        console2.log("");
        console2.log("--- Part 6: Agent Bond Operations ---");

        // Agent tops up bond
        uint256 agentKey = vm.envUint("AGENT_KEY");
        vm.startBroadcast(agentKey);

        ProposalRegistry proposals = ProposalRegistry(payable(PROPOSAL_REG));
        proposals.postBond{value: 0.005 ether}();
        console2.log("Agent posted additional 0.005 ETH bond");

        // Agent withdraws small amount
        proposals.withdrawBond(0.001 ether);
        console2.log("Agent withdrew 0.001 ETH from bond");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 7: Multi-Agent Authorization
        // ═══════════════════════════════════════
        vm.startBroadcast(deployerKey);

        console2.log("");
        console2.log("--- Part 7: Multi-Agent Management ---");

        // Create and authorize additional agent addresses
        address agent2 = address(0xA2A2);
        address agent3 = address(0xA3A3);
        address agent4 = address(0xA4A4);

        proposals.setAuthorizedAgent(agent2, true);
        console2.log("Authorized agent2:", vm.toString(agent2));

        proposals.setAuthorizedAgent(agent3, true);
        console2.log("Authorized agent3:", vm.toString(agent3));

        proposals.setAuthorizedAgent(agent4, true);
        console2.log("Authorized agent4:", vm.toString(agent4));

        // Deauthorize agent3
        proposals.setAuthorizedAgent(agent3, false);
        console2.log("Deauthorized agent3:", vm.toString(agent3));

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 8: Emergency Drills
        // ═══════════════════════════════════════
        console2.log("");
        console2.log("--- Part 8: Emergency Drills ---");

        // Guardian pauses vault
        uint256 guardianKey = vm.envUint("GUARDIAN_KEY");
        vm.startBroadcast(guardianKey);

        vault.emergencyPause();
        console2.log("Guardian: vault PAUSED");

        vm.stopBroadcast();

        // Safe unpauses
        vm.startBroadcast(deployerKey);

        vault.emergencyUnpause();
        console2.log("Safe: vault UNPAUSED");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 9: Circuit Breaker Drills (all adapters)
        // ═══════════════════════════════════════
        console2.log("");
        console2.log("--- Part 9: Circuit Breaker Drills ---");

        vm.startBroadcast(guardianKey);

        // Trip all adapter breakers
        ERC20Adapter(ERC20_ADAPTER).tripBreaker();
        console2.log("ERC20Adapter: breaker TRIPPED");

        AaveAdapter(AAVE_ADAPTER).tripBreaker();
        console2.log("AaveAdapter: breaker TRIPPED");

        PendleAdapter(PENDLE_ADAPTER).tripBreaker();
        console2.log("PendleAdapter: breaker TRIPPED");

        RobinhoodRWAAdapter(RWA_ADAPTER).tripBreaker();
        console2.log("RobinhoodRWAAdapter: breaker TRIPPED");

        // Reset all breakers
        ERC20Adapter(ERC20_ADAPTER).resetBreaker();
        console2.log("ERC20Adapter: breaker RESET");

        AaveAdapter(AAVE_ADAPTER).resetBreaker();
        console2.log("AaveAdapter: breaker RESET");

        PendleAdapter(PENDLE_ADAPTER).resetBreaker();
        console2.log("PendleAdapter: breaker RESET");

        RobinhoodRWAAdapter(RWA_ADAPTER).resetBreaker();
        console2.log("RobinhoodRWAAdapter: breaker RESET");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 10: RWA Adapter - Asset Listing
        // ═══════════════════════════════════════
        console2.log("");
        console2.log("--- Part 10: RWA Asset Listing ---");

        vm.startBroadcast(guardianKey);

        RobinhoodRWAAdapter rwa = RobinhoodRWAAdapter(RWA_ADAPTER);

        rwa.setListed(address(mockSPY), true);
        console2.log("Listed mSPY on RWA exchange");

        rwa.setListed(address(mockTBILL), true);
        console2.log("Listed mTBILL on RWA exchange");

        // Simulate a delisting event
        address mockDELISTED = address(0xDEAD);
        rwa.setListed(mockDELISTED, true);
        console2.log("Listed mockDELISTED for delisting test");

        rwa.setListed(mockDELISTED, false);
        console2.log("Delisted mockDELISTED");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 11: Additional Deposits (3rd round)
        // ═══════════════════════════════════════
        vm.startBroadcast(deployerKey);

        console2.log("");
        console2.log("--- Part 11: Third Deposit Round ---");

        mockARB.approve(VAULT, 50_000 * 1e18);
        vault.deposit(address(mockARB), 50_000 * 1e18);
        console2.log("Deposited: 50,000 mARB (3rd round)");

        mockSPY.approve(VAULT, 200 * 1e18);
        vault.deposit(address(mockSPY), 200 * 1e18);
        console2.log("Deposited: 200 mSPY (3rd round)");

        mockTBILL.approve(VAULT, 50_000 * 1e18);
        vault.deposit(address(mockTBILL), 50_000 * 1e18);
        console2.log("Deposited: 50,000 mTBILL (3rd round)");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 12: Safe Withdraw (emergency path)
        // ═══════════════════════════════════════
        vm.startBroadcast(deployerKey);

        console2.log("");
        console2.log("--- Part 12: Emergency Withdraw ---");

        vault.withdraw(address(mockUSDC), 10_000 * 1e6, deployer);
        console2.log("Withdrew: 10,000 mUSDC to deployer");

        vault.withdraw(address(mockWETH), 5 * 1e18, deployer);
        console2.log("Withdrew: 5 mWETH to deployer");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 13: Deregister and Re-register Asset
        // ═══════════════════════════════════════
        vm.startBroadcast(deployerKey);

        console2.log("");
        console2.log("--- Part 13: Asset Deregister/Re-register ---");

        // Deploy a temporary token, register, then deregister
        MockERC20 tempToken = new MockERC20("Temp Token", "TEMP", 18);
        console2.log("Deployed temp token:", address(tempToken));

        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: address(tempToken),
            decimals: 18,
            isStable: false,
            isLiquid: true,
            protocol: ITreasuryVault.Protocol.WALLET,
            adapter: address(0),
            active: true
        }));
        console2.log("Registered: TEMP");

        vault.deregisterAsset(address(tempToken));
        console2.log("Deregistered: TEMP");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 14: Oracle Configuration
        // ═══════════════════════════════════════
        vm.startBroadcast(deployerKey);

        console2.log("");
        console2.log("--- Part 14: Oracle Configuration ---");

        OracleAggregator oracle = OracleAggregator(ORACLE);

        // Set feeds for mock tokens (using placeholder feed addresses)
        oracle.setFeed(address(mockUSDC), address(0x1001), bytes32(uint256(0x2001)));
        console2.log("Set feed: mUSDC (chainlink + pyth)");

        oracle.setFeed(address(mockWETH), address(0x1002), bytes32(uint256(0x2002)));
        console2.log("Set feed: mWETH");

        oracle.setFeed(address(mockARB), address(0x1003), bytes32(uint256(0x2003)));
        console2.log("Set feed: mARB");

        // Set RWA oracle for tokenized assets
        oracle.setRwaOracle(address(mockSPY), address(0x3001));
        console2.log("Set RWA oracle: mSPY");

        oracle.setRwaOracle(address(mockTBILL), address(0x3002));
        console2.log("Set RWA oracle: mTBILL");

        // Adjust staleness
        oracle.setMaxStaleness(1800); // 30 minutes
        console2.log("Set max staleness: 30 min");

        oracle.setMaxStaleness(3600); // back to 1 hour
        console2.log("Set max staleness: 1 hour (final)");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 15: Second Emergency Drill
        // ═══════════════════════════════════════
        console2.log("");
        console2.log("--- Part 15: Second Emergency Drill ---");

        vm.startBroadcast(guardianKey);
        vault.emergencyPause();
        console2.log("Guardian: vault PAUSED (drill 2)");
        vm.stopBroadcast();

        vm.startBroadcast(deployerKey);
        vault.emergencyUnpause();
        console2.log("Safe: vault UNPAUSED (drill 2)");

        // One more deposit after unpause to confirm operations resume
        mockUSDC.approve(VAULT, 50_000 * 1e6);
        vault.deposit(address(mockUSDC), 50_000 * 1e6);
        console2.log("Deposited: 50,000 mUSDC (post-drill deposit)");

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // PART 16: Propose second policy
        // ═══════════════════════════════════════
        vm.startBroadcast(deployerKey);

        console2.log("");
        console2.log("--- Part 16: Propose Aggressive Policy ---");

        // Overwrite pending policy with a new one
        bytes memory aggressivePolicy = abi.encode(
            "aggressive-v1",
            uint256(20), // 20% stables
            uint256(40), // 40% DeFi yield
            uint256(40)  // 40% RWA
        );
        policyReg.proposeUpdate(aggressivePolicy, noConstraints);
        console2.log("Proposed: aggressive-v1 policy");
        console2.log("  Pending hash:", vm.toString(policyReg.pendingPolicyHash()));

        vm.stopBroadcast();

        // ═══════════════════════════════════════
        // SUMMARY
        // ═══════════════════════════════════════
        console2.log("");
        console2.log("============================================");
        console2.log("  INTERACTION SUITE COMPLETE");
        console2.log("============================================");
        console2.log("Mock tokens deployed:");
        console2.log("  mUSDC:  ", address(mockUSDC));
        console2.log("  mWETH:  ", address(mockWETH));
        console2.log("  mARB:   ", address(mockARB));
        console2.log("  mSPY:   ", address(mockSPY));
        console2.log("  mTBILL: ", address(mockTBILL));
        console2.log("");
        console2.log("Vault balances (after all ops):");
        console2.log("  mUSDC:  340,000");
        console2.log("  mWETH:  55");
        console2.log("  mARB:   150,000");
        console2.log("  mSPY:   700");
        console2.log("  mTBILL: 150,000");
        console2.log("============================================");

        // Write mock token addresses
        string memory json = string.concat(
            '{"mock_usdc":"', vm.toString(address(mockUSDC)),
            '","mock_weth":"', vm.toString(address(mockWETH)),
            '","mock_arb":"', vm.toString(address(mockARB)),
            '","mock_spy":"', vm.toString(address(mockSPY)),
            '","mock_tbill":"', vm.toString(address(mockTBILL)),
            '","temp_token":"', vm.toString(address(tempToken)), '"}'
        );
        vm.writeFile("./deployments/mock_tokens.json", json);
        console2.log("Mock token addresses saved to deployments/mock_tokens.json");
    }
}
