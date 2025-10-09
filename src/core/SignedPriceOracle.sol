// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title SignedPriceOracle
/// @notice MVP oracle supports keeper-set prices and optional ECDSA signatures
contract SignedPriceOracle is Initializable, AccessControlUpgradeable, UUPSUpgradeable, EIP712Upgradeable {
    using ECDSA for bytes32;

    struct Price { uint256 priceX1e18; uint64 ts; }

    mapping(address => Price) public prices;
    address public signer;
    uint64 public maxStale;
    
    // EIP-712 constants
    bytes32 public constant PRICE_TYPEHASH = keccak256("Price(address asset,uint256 priceX1e18,uint64 ts,uint256 nonce)");
    mapping(address => uint256) public nonces; // Nonce for each signer to prevent replay attacks

    event PriceUpdated(address indexed asset, uint256 priceX1e18, uint64 ts, address indexed updater);
    event SignerSet(address indexed signer);
    event MaxStaleSet(uint64 maxStale);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address admin, address _signer, uint64 _maxStale) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __EIP712_init("SignedPriceOracle", "1");
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        _grantRole(Constants.PRICE_KEEPER, admin);
        signer = _signer;
        maxStale = _maxStale == 0 ? Constants.DEFAULT_MAX_STALE : _maxStale;
        emit SignerSet(_signer);
        emit MaxStaleSet(maxStale);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function setSigner(address _signer) external onlyRole(Constants.DEFAULT_ADMIN) {
        signer = _signer; emit SignerSet(_signer);
    }

    function setMaxStale(uint256 _max) external onlyRole(Constants.PRICE_KEEPER) {
        maxStale = uint64(_max); emit MaxStaleSet(uint64(_max));
    }

    function getMaxStale() external view returns (uint256) {
        return maxStale;
    }

    // Test helper / keeper path
    function setPrice(address asset, uint256 priceX1e18, uint64 ts) external onlyRole(Constants.PRICE_KEEPER) {
        prices[asset] = Price(priceX1e18, ts);
        emit PriceUpdated(asset, priceX1e18, ts, msg.sender);
    }

    function setPriceSigned(address asset, uint256 priceX1e18, uint64 ts, bytes calldata signature) external {
        uint256 nonce = nonces[signer];
        
        // Create EIP-712 structured data hash
        bytes32 structHash = keccak256(abi.encode(
            PRICE_TYPEHASH,
            asset,
            priceX1e18,
            ts,
            nonce
        ));
        
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = ECDSA.recover(digest, signature);
        require(recovered == signer, "bad sig");
        
        // Increment nonce to prevent replay attacks
        nonces[signer]++;
        
        prices[asset] = Price(priceX1e18, ts);
        emit PriceUpdated(asset, priceX1e18, ts, msg.sender);
    }

    function setPriceSignedLegacy(address asset, uint256 priceX1e18, uint64 ts, bytes calldata signature) external {
        // Legacy method using personal sign for backward compatibility
        bytes32 digest = keccak256(abi.encode(asset, priceX1e18, ts, address(this))).toEthSignedMessageHash();
        address recovered = ECDSA.recover(digest, signature);
        require(recovered == signer, "bad sig");
        prices[asset] = Price(priceX1e18, ts);
        emit PriceUpdated(asset, priceX1e18, ts, msg.sender);
    }

    function getPrice(address asset) external view returns (uint256 priceX1e18, uint64 ts, bool isStale) {
        Price memory p = prices[asset];
        priceX1e18 = p.priceX1e18; ts = p.ts;
        // If maxStale == 0, treat as never stale (unless price ts == 0)
        if (p.ts == 0) {
            isStale = true;
        } else if (maxStale == 0) {
            isStale = false;
        } else {
            isStale = (block.timestamp - p.ts > maxStale);
        }
    }

    uint256[50] private __gap;
}
