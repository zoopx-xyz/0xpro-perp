// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Constants} from "../lib/Constants.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {MockzUSD} from "../src/tokens/MockzUSD.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {PerpEngine} from "../src/core/PerpEngine.sol";
import {RiskConfig} from "../src/core/RiskConfig.sol";
import {FundingModule} from "../src/core/FundingModule.sol";
import {TreasurySpoke} from "../src/core/TreasurySpoke.sol";
import {FeeSplitterSpoke} from "../src/core/FeeSplitterSpoke.sol";
import {MarketFactory} from "../src/core/MarketFactory.sol";

contract Deploy is Script {
    address public admin;

    function run() external {
        vm.startBroadcast();
        admin = msg.sender;

        // Deploy tokens
        MockzUSD z = new MockzUSD();
        // 12 mocks
        MockERC20 mockETH = new MockERC20("mockETH", "mETH", 18);
        MockERC20 mockWETH = new MockERC20("mockWETH", "mWETH", 18);
        MockERC20 mockBTC = new MockERC20("mockBTC", "mBTC", 8);
        MockERC20 mockWBTC = new MockERC20("mockWBTC", "mWBTC", 8);
        MockERC20 mockSOL = new MockERC20("mockSOL", "mSOL", 9);
        MockERC20 mockKDA = new MockERC20("mockKDA", "mKDA", 12);
        MockERC20 mockPOL = new MockERC20("mockPOL", "mPOL", 18);
        MockERC20 mockZPX = new MockERC20("mockZPX", "mZPX", 18);
        MockERC20 mockUSDC = new MockERC20("mockUSDC", "mUSDC", 6);
        MockERC20 mockUSDT = new MockERC20("mockUSDT", "mUSDT", 6);
        MockERC20 mockPYUSD = new MockERC20("mockPYUSD", "mPYUSD", 6);
        MockERC20 mockUSD1 = new MockERC20("mockUSD1", "mUSD1", 18);

        // Deploy implementations
        CollateralManager cmImpl = new CollateralManager();
        SignedPriceOracle spoImpl = new SignedPriceOracle();
        OracleRouter orImpl = new OracleRouter();
        MarginVaultV2 mvImpl = new MarginVaultV2();
        PerpEngine peImpl = new PerpEngine();
        RiskConfig rcImpl = new RiskConfig();
        FundingModule fmImpl = new FundingModule();
        TreasurySpoke tsImpl = new TreasurySpoke();
        FeeSplitterSpoke fsImpl = new FeeSplitterSpoke();
        MarketFactory mfImpl = new MarketFactory();

        // Deploy proxies
        CollateralManager cm = CollateralManager(address(new ERC1967Proxy(address(cmImpl), "")));
        SignedPriceOracle spo = SignedPriceOracle(address(new ERC1967Proxy(address(spoImpl), "")));
        OracleRouter orac = OracleRouter(address(new ERC1967Proxy(address(orImpl), "")));
        MarginVaultV2 mv = MarginVaultV2(address(new ERC1967Proxy(address(mvImpl), "")));
        PerpEngine pe = PerpEngine(address(new ERC1967Proxy(address(peImpl), "")));
        RiskConfig rc = RiskConfig(address(new ERC1967Proxy(address(rcImpl), "")));
        FundingModule fm = FundingModule(address(new ERC1967Proxy(address(fmImpl), "")));
        TreasurySpoke ts = TreasurySpoke(address(new ERC1967Proxy(address(tsImpl), "")));
        FeeSplitterSpoke fs = FeeSplitterSpoke(address(new ERC1967Proxy(address(fsImpl), "")));
        MarketFactory mf = MarketFactory(address(new ERC1967Proxy(address(mfImpl), "")));

        // Initialize
        spo.initialize(admin, address(0), 300);
        orac.initialize(admin);
        cm.initialize(admin, address(orac));
        mv.initialize(admin, address(cm));
        pe.initialize(admin, address(mv));
        rc.initialize(admin);
        fm.initialize(admin);
        ts.initialize(admin);
        fs.initialize(admin);
        mf.initialize(admin);

        // Register adapters
        orac.registerAdapter(address(mockETH), address(spo));
        orac.registerAdapter(address(mockWETH), address(spo));
        orac.registerAdapter(address(mockBTC), address(spo));
        orac.registerAdapter(address(mockWBTC), address(spo));
        orac.registerAdapter(address(mockSOL), address(spo));
        orac.registerAdapter(address(mockKDA), address(spo));
        orac.registerAdapter(address(mockPOL), address(spo));
        orac.registerAdapter(address(mockZPX), address(spo));
        orac.registerAdapter(address(mockUSDC), address(spo));
        orac.registerAdapter(address(mockUSDT), address(spo));
        orac.registerAdapter(address(mockPYUSD), address(spo));
        orac.registerAdapter(address(mockUSD1), address(spo));

        // Set asset configs (LTVs & decimals)
        cm.setAssetConfig(address(mockETH), true, 5000, address(orac), 18);
        cm.setAssetConfig(address(mockWETH), true, 5000, address(orac), 18);
        cm.setAssetConfig(address(mockBTC), true, 5000, address(orac), 8);
        cm.setAssetConfig(address(mockWBTC), true, 5000, address(orac), 8);
        cm.setAssetConfig(address(mockSOL), true, 5000, address(orac), 9);
        cm.setAssetConfig(address(mockKDA), true, 5000, address(orac), 12);
        cm.setAssetConfig(address(mockPOL), true, 5000, address(orac), 18);
        cm.setAssetConfig(address(mockZPX), true, 5000, address(orac), 18);
        cm.setAssetConfig(address(mockUSDC), true, 10000, address(orac), 6);
        cm.setAssetConfig(address(mockUSDT), true, 10000, address(orac), 6);
        cm.setAssetConfig(address(mockPYUSD), true, 10000, address(orac), 6);
        cm.setAssetConfig(address(mockUSD1), true, 10000, address(orac), 18);

        // Seed prices (example values, in 1e18)
        spo.setPrice(address(mockETH), 2000e18, uint64(block.timestamp));
        spo.setPrice(address(mockWETH), 2000e18, uint64(block.timestamp));
        spo.setPrice(address(mockBTC), 60000e18, uint64(block.timestamp));
        spo.setPrice(address(mockWBTC), 60000e18, uint64(block.timestamp));
        spo.setPrice(address(mockSOL), 150e18, uint64(block.timestamp));
        spo.setPrice(address(mockKDA), 1e18, uint64(block.timestamp));
        spo.setPrice(address(mockPOL), 1e18, uint64(block.timestamp));
        spo.setPrice(address(mockZPX), 0.2e18, uint64(block.timestamp));
        spo.setPrice(address(mockUSDC), 1e18, uint64(block.timestamp));
        spo.setPrice(address(mockUSDT), 1e18, uint64(block.timestamp));
        spo.setPrice(address(mockPYUSD), 1e18, uint64(block.timestamp));
        spo.setPrice(address(mockUSD1), 1e18, uint64(block.timestamp));

        vm.stopBroadcast();
    }
}
