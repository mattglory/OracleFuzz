// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9;

import {Test, console2} from "forge-std/Test.sol";
import {KineticFtsoChaosMock} from "./KineticFtsoChaosMock.sol";
import {MockDecimalsToken} from "./MockDecimalsToken.sol";

// OracleFuzz x Kinetic Market integration
//
// Points OracleFuzz's chaos-injection mock at the REAL, deployed-on-Flare
// `ProtocolFTSOV3Oracle` from kinetic-market/public-money-market-contracts
// (installed as a `forge install` dependency in lib/, unmodified). This is not a
// toy example - it fuzzes the actual staleness-enforcement logic a live Flare
// money market relies on to price collateral.
//
// `ProtocolFTSOV3Oracle` is pinned to `pragma solidity 0.5.17`, which cannot be
// directly imported into this 0.8.x file (solc compiles an import graph with a
// single compiler version; 0.5.17 and 0.8.19+ can't share one invocation). It is
// instead deployed via forge-std's `deployCode`, which reads the already-compiled
// artifact and deploys its bytecode directly - the standard Foundry pattern for
// testing across incompatible pragma versions. Every call into it afterwards is
// a normal external call, ABI-selector-matched, version-agnostic.
bytes21 constant FEED_ID = bytes21(uint168(uint256(keccak256("FLR/USD"))));
uint64 constant MAX_STALE_PERIOD = 300; // matches PriceConsumer's threshold in the M1 demo

contract Handler is Test {
    address public oracle; // ProtocolFTSOV3Oracle, deployed via deployCode
    KineticFtsoChaosMock public mock;
    address public token;

    bool public everReturnedStaleValue;
    uint256 public callCount;
    uint256 public revertCount;

    constructor(address _oracle, KineticFtsoChaosMock _mock, address _token) {
        oracle = _oracle;
        mock = _mock;
        token = _token;
        mock.setFeedData(FEED_ID, 100_000, 5); // arbitrary sane starting price
    }

    function updatePrice(int32 newValue, int8 decimals) public {
        newValue = int32(uint32(bound(uint256(uint32(newValue)), 1, uint256(uint32(type(int32).max)))));
        decimals = int8(uint8(bound(uint256(uint8(decimals)), 0, 18)));
        mock.setFeedData(FEED_ID, uint256(uint32(newValue)), decimals);
    }

    function goStale(uint64 secondsStale) public {
        secondsStale = uint64(bound(secondsStale, 0, 3650 days));
        mock.setStale(FEED_ID, secondsStale);
    }

    function warp(uint256 secondsForward) public {
        secondsForward = bound(secondsForward, 0, 30 days);
        vm.warp(block.timestamp + secondsForward);
    }

    /// @notice Calls Kinetic's real getPrice(token) and checks, from OUTSIDE the
    /// oracle, whether the feed it must have read was stale at call time. This is
    /// the ground-truth check - it does not trust the oracle's own revert behavior.
    function queryOracle() public {
        (,, uint64 tsBefore) = mock.getFeedById(FEED_ID);
        bool wasStaleAtCallTime = (block.timestamp - tsBefore) > MAX_STALE_PERIOD;

        callCount++;
        (bool success, bytes memory data) = oracle.staticcall(abi.encodeWithSignature("getPrice(address)", token));
        if (success) {
            uint256 price = abi.decode(data, (uint256));
            if (wasStaleAtCallTime && price > 0) {
                everReturnedStaleValue = true;
            }
        } else {
            revertCount++;
        }
    }
}

/// @notice Kinetic's ProtocolFTSOV3Oracle.getFTSOPrice() enforces:
/// `require(block.timestamp - _timestamp <= maxStalePeriod, "stale price")`.
/// This invariant fuzzes price updates, staleness, and time warps against the
/// REAL contract and asserts that guard never lets a stale-derived price through -
/// the same property class the M1 PriceConsumer demo proved OracleFuzz can catch
/// when it's MISSING. Here we're validating it's actually present and effective
/// in a live ecosystem protocol, not a toy example.
contract Kinetic_FTSOV3Oracle_InvariantTest is Test {
    address oracle;
    KineticFtsoChaosMock mock;
    MockDecimalsToken token;
    Handler handler;

    function setUp() public {
        // Deploy the real, unmodified 0.5.17 contract via its compiled artifact.
        oracle = deployCode("ProtocolFTSOV3Oracle.sol:ProtocolFTSOV3Oracle", abi.encode("kFLR"));
        mock = new KineticFtsoChaosMock();
        token = new MockDecimalsToken(18);

        // setFTSOV2(address) - sanity-checks by calling FTSO_PROTOCOL_ID() on it.
        (bool ok1,) = oracle.call(abi.encodeWithSignature("setFTSOV2(address)", address(mock)));
        require(ok1, "setFTSOV2 failed");

        // setTokenConfig((address,bytes21,uint64,address)) - the real TokenConfig
        // struct layout from ProtocolFTSOV3Oracle.sol.
        (bool ok2,) = oracle.call(
            abi.encodeWithSignature(
                "setTokenConfig((address,bytes21,uint64,address))", address(token), FEED_ID, MAX_STALE_PERIOD, address(0)
            )
        );
        require(ok2, "setTokenConfig failed");

        handler = new Handler(oracle, mock, address(token));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 500
    /// forge-config: default.invariant.depth = 50
    function invariant_NeverReturnsStalePrice() public view {
        assertFalse(
            handler.everReturnedStaleValue(), "Kinetic's ProtocolFTSOV3Oracle accepted/returned a stale price"
        );
    }
}

/// @notice Sanity check that the invariant above isn't vacuously passing because
/// every staticcall into the oracle happens to fail. Confirms both a real
/// non-stale success path and a real stale-triggered revert actually occur.
contract Kinetic_FTSOV3Oracle_DiagnosticTest is Test {
    address oracle;
    KineticFtsoChaosMock mock;
    MockDecimalsToken token;

    function setUp() public {
        oracle = deployCode("ProtocolFTSOV3Oracle.sol:ProtocolFTSOV3Oracle", abi.encode("kFLR"));
        mock = new KineticFtsoChaosMock();
        token = new MockDecimalsToken(18);
        (bool ok1,) = oracle.call(abi.encodeWithSignature("setFTSOV2(address)", address(mock)));
        require(ok1, "setFTSOV2 failed");
        (bool ok2,) = oracle.call(
            abi.encodeWithSignature(
                "setTokenConfig((address,bytes21,uint64,address))", address(token), FEED_ID, MAX_STALE_PERIOD, address(0)
            )
        );
        require(ok2, "setTokenConfig failed");
        mock.setFeedData(FEED_ID, 100_000, 5);
    }

    function test_HappyPathReturnsRealPrice() public {
        (bool success, bytes memory data) = oracle.staticcall(abi.encodeWithSignature("getPrice(address)", address(token)));
        assertTrue(success, "fresh price should succeed");
        uint256 price = abi.decode(data, (uint256));
        assertGt(price, 0, "fresh price should be nonzero");
        console2.log("fresh price:", price);
    }

    function test_StalePriceReverts() public {
        vm.warp(block.timestamp + MAX_STALE_PERIOD + 1);
        (bool success, bytes memory data) = oracle.staticcall(abi.encodeWithSignature("getPrice(address)", address(token)));
        assertFalse(success, "stale price should revert, not succeed");
        console2.logBytes(data);
    }
}
