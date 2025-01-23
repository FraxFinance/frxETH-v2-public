// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

interface ISfrxEthUsdDualOracle {
    function BASE_TOKEN_0() external view returns (address);
    function BASE_TOKEN_0_DECIMALS() external view returns (uint256);
    function BASE_TOKEN_1() external view returns (address);
    function BASE_TOKEN_1_DECIMALS() external view returns (uint256);
    function CURVE_POOL_EMA_PRICE_ORACLE() external view returns (address);
    function CURVE_POOL_EMA_PRICE_ORACLE_PRECISION() external view returns (uint256);
    function ETH_USD_CHAINLINK_FEED_ADDRESS() external view returns (address);
    function ETH_USD_CHAINLINK_FEED_DECIMALS() external view returns (uint8);
    function ETH_USD_CHAINLINK_FEED_PRECISION() external view returns (uint256);
    function FRAX_USD_CHAINLINK_FEED_ADDRESS() external view returns (address);
    function FRAX_USD_CHAINLINK_FEED_DECIMALS() external view returns (uint8);
    function FRAX_USD_CHAINLINK_FEED_PRECISION() external view returns (uint256);
    function NORMALIZATION_0() external view returns (int256);
    function NORMALIZATION_1() external view returns (int256);
    function ORACLE_PRECISION() external view returns (uint256);
    function QUOTE_TOKEN_0() external view returns (address);
    function QUOTE_TOKEN_0_DECIMALS() external view returns (uint256);
    function QUOTE_TOKEN_1() external view returns (address);
    function QUOTE_TOKEN_1_DECIMALS() external view returns (uint256);
    function SFRXETH_ERC4626() external view returns (address);
    function TWAP_PRECISION() external view returns (uint128);
    function UNISWAP_V3_TWAP_BASE_TOKEN() external view returns (address);
    function UNISWAP_V3_TWAP_QUOTE_TOKEN() external view returns (address);
    function UNI_V3_PAIR_ADDRESS() external view returns (address);
    function acceptTransferTimelock() external;
    function addRoundData(address _fraxOracle) external;
    function calculatePrices(
        uint256 _wethPerFrxEthCurveEma,
        uint256 _fraxPerFrxEthTwap,
        bool _isBadDataEthUsdChainlink,
        uint256 _usdPerEthChainlink,
        bool _isBadDataFraxUsdChainlink,
        uint256 _usdPerFraxChainlink,
        uint256 _frxEthPerSfrxEth
    ) external view returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh);
    function decimals() external pure returns (uint8);
    function getCurvePoolToken1EmaPrice() external view returns (uint256 _emaPrice);
    function getEthUsdChainlinkPrice() external view returns (bool _isBadData, uint256 _updatedAt, uint256 _usdPerEth);
    function getFraxPerFrxEthUniV3Twap() external view returns (uint256 _fraxPerFrxEthTwap);
    function getFraxUsdChainlinkPrice()
        external
        view
        returns (bool _isBadData, uint256 _updatedAt, uint256 _usdPerFrax);
    function getFrxEthPerSfrxEthErc4626Vault() external view returns (uint256 _frxEthPerSfrxEth);
    function getPrices() external view returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh);
    function getPricesNormalized()
        external
        view
        returns (bool _isBadDataNormal, uint256 _priceLowNormal, uint256 _priceHighNormal);
    function getUniswapV3Twap() external view returns (uint256 _twap);
    function getUsdPerEthChainlink() external view returns (bool _isBadData, uint256 _usdPerEth);
    function getUsdPerFraxChainlink() external view returns (bool _isBadData, uint256 _usdPerFrax);
    function getWethPerFrxEthCurveEma() external view returns (uint256 _wethPerFrxEth);
    function maximumCurvePoolEma() external view returns (uint256);
    function maximumEthUsdOracleDelay() external view returns (uint256);
    function maximumFraxUsdOracleDelay() external view returns (uint256);
    function minimumCurvePoolEma() external view returns (uint256);
    function name() external pure returns (string memory _name);
    function pendingTimelockAddress() external view returns (address);
    function renounceTimelock() external;
    function setMaximumCurvePoolEma(uint256 _maximumPrice) external;
    function setMaximumEthUsdOracleDelay(uint256 _newMaxOracleDelay) external;
    function setMaximumFraxUsdOracleDelay(uint256 _newMaxOracleDelay) external;
    function setMinimumCurvePoolEma(uint256 _minimumPrice) external;
    function setTwapDuration(uint32 _newTwapDuration) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function timelockAddress() external view returns (address);
    function transferTimelock(address _newTimelock) external;
    function twapDuration() external view returns (uint32);
    function version() external pure returns (uint256 _major, uint256 _minor, uint256 _patch);
}
