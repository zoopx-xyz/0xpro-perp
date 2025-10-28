// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IL2ToL2CrossDomainMessenger} from "../src/bridge/op/IL2ToL2CrossDomainMessenger.sol";
import {OpL2L2Sender} from "../src/bridge/op/OpL2L2Sender.sol";
import {OpL2L2Receiver} from "../src/bridge/op/OpL2L2Receiver.sol";
import {AssetMapper} from "../src/bridge/AssetMapper.sol";
import {BridgeAdapter} from "../src/bridge/BridgeAdapter.sol";
import {EscrowGateway} from "../src/satellite/EscrowGateway.sol";
import {IBridgeableVault} from "../src/core/interfaces/IBridgeableVault.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {Constants} from "../lib/Constants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockL2ToL2Messenger is IL2ToL2CrossDomainMessenger {
    address private _xSender;
    address public lastTarget;
    bytes public lastMessage;

    function setXSender(address s) external { _xSender = s; }

    function sendMessage(address target, bytes calldata message, uint32 /*minGasLimit*/ ) external {
        lastTarget = target;
        lastMessage = message;
        (bool ok, bytes memory ret) = target.call(message);
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    function xDomainMessageSender() external view returns (address) {
        return _xSender;
    }
}

contract MockVault is IBridgeableVault {
    address public lastUser;
    address public lastAsset;
    uint256 public lastAmount;
    bytes32 public lastId;

    function mintCreditFromBridge(address user, address asset, uint256 amount, bytes32 depositId) external {
        lastUser = user; lastAsset = asset; lastAmount = amount; lastId = depositId;
    }
    function burnCreditForBridge(address /*user*/, address /*asset*/, uint256 /*amount*/, bytes32 /*withdrawalId*/) external {}
}

contract OpL2L2AdaptersTest is Test {
    MockL2ToL2Messenger messenger;
    OpL2L2Sender sender;
    OpL2L2Receiver receiver;
    AssetMapper mapper;
    BridgeAdapter bridge;
    EscrowGateway escrow;
    MockVault vault;

    MockERC20 satToken;
    address baseToken = address(0xBABE);

    address admin = address(this);
    address user = address(0xA11CE);

    bytes32 chain = keccak256("dst-chain");

    function setUp() public {
        messenger = new MockL2ToL2Messenger();

    OpL2L2Sender sImpl = new OpL2L2Sender();
    bytes memory sInit = abi.encodeWithSelector(OpL2L2Sender.initialize.selector, admin, address(messenger), address(0), 1_000_000);
    sender = OpL2L2Sender(address(new ERC1967Proxy(address(sImpl), sInit)));

    OpL2L2Receiver rImpl = new OpL2L2Receiver();
    bytes memory rInit = abi.encodeWithSelector(OpL2L2Receiver.initialize.selector, admin, address(messenger), address(sender));
    receiver = OpL2L2Receiver(address(new ERC1967Proxy(address(rImpl), rInit)));

    // wire sender remote receiver now that receiver exists
    sender.setRemoteReceiver(address(receiver));

    AssetMapper mImpl = new AssetMapper();
    mapper = AssetMapper(address(new ERC1967Proxy(address(mImpl), abi.encodeWithSelector(AssetMapper.initialize.selector, admin))));

        vault = new MockVault();
    BridgeAdapter bImpl = new BridgeAdapter();
    bridge = BridgeAdapter(address(new ERC1967Proxy(address(bImpl), abi.encodeWithSelector(BridgeAdapter.initialize.selector, admin, address(vault)))));

    EscrowGateway eImpl = new EscrowGateway();
    escrow = EscrowGateway(address(new ERC1967Proxy(address(eImpl), abi.encodeWithSelector(EscrowGateway.initialize.selector, admin))));

        // Roles: grant receiver permission to call bridge and escrow on message processing
        vm.startPrank(admin);
        // MESSAGE_RECEIVER_ROLE must be granted to receiver
        bridge.grantRole(Constants.MESSAGE_RECEIVER_ROLE, address(receiver));
        escrow.grantRole(Constants.MESSAGE_RECEIVER_ROLE, address(receiver));
        vm.stopPrank();

        // Wire receiver endpoints and mapper
        receiver.setBridgeAdapter(address(bridge));
        receiver.setEscrowGateway(address(escrow));
        receiver.setAssetMapper(address(mapper));

        // Wire sender mapper as well
        sender.setAssetMapper(address(mapper));

        // Token setup on satellite
        satToken = new MockERC20("SAT", "SAT", 18);
        satToken.transferOwnership(admin);
        // Map base<->sat for chain
        mapper.setMapping(chain, address(satToken), baseToken);

        // Support satellite token in escrow and fund escrow with liquidity for releases
        escrow.setSupportedAsset(address(satToken), true);
        satToken.mint(address(escrow), 1_000_000 ether);
    }

    function testReceiverOnDepositCreditsBridge() public {
        // Simulate cross-domain context
        messenger.setXSender(address(sender));
        address satelliteAsset = address(satToken);
        uint256 amount = 123 ether;
        bytes32 depId = keccak256("dep-1");

        // Call via messenger to satisfy onlyMessenger
        bytes memory payload = abi.encodeWithSignature(
            "onDepositMessage(address,address,uint256,bytes32,bytes32)", user, satelliteAsset, amount, depId, chain
        );
        messenger.sendMessage(address(receiver), payload, 0);

        // Bridge should have minted to user with base asset
    assertEq(vault.lastUser(), user);
    assertEq(vault.lastAsset(), baseToken);
    assertEq(vault.lastAmount(), amount);
    assertEq(vault.lastId(), depId);

    // Replay should revert when called again via messenger
    vm.expectRevert(bytes("replayed"));
    messenger.sendMessage(address(receiver), payload, 0);
    }

    function testReceiverOnDepositOnlyMessenger() public {
        // call directly without messenger context
        vm.expectRevert(bytes("not messenger"));
        receiver.onDepositMessage(user, address(satToken), 1 ether, keccak256("x"), chain);
    }

    function testSenderWithdrawalAndReceiverRelease() public {
        messenger.setXSender(address(sender));

        uint256 amount = 50 ether;
        vm.prank(user);
        sender.sendWithdrawal(user, baseToken, amount, keccak256("wd1"), chain);

        // Sender should have sent message to receiver with mapped satellite asset
    assertEq(messenger.lastTarget(), address(receiver));

        // After message execution, escrow should have released tokens to user
    assertEq(satToken.balanceOf(user), amount);
    }

    function testReceiverWithdrawalBadSenderReverts() public {
        // Set spoofed xDomain sender and call via messenger
        messenger.setXSender(address(0xDEAD));
        bytes memory payload = abi.encodeWithSignature(
            "onWithdrawalMessage(address,address,uint256,bytes32,bytes32)", user, address(satToken), 1 ether, keccak256("w"), chain
        );
        vm.expectRevert(bytes("bad xSender"));
        messenger.sendMessage(address(receiver), payload, 0);
    }
}
