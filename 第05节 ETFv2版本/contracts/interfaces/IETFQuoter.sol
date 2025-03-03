// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IETFQuoter {
    error SameTokens();

    function weth() external view returns (address);

    function usdc() external view returns (address);

    function getAllPaths(//通过A跟B，去遍历所有的Path
        address tokenA,
        address tokenB
    ) external view returns (bytes[] memory paths);//所有的路径

    function quoteInvestWithToken(//核心：etf等三个参数
        address etf,
        address srcToken,//如果是ETH的话，会转换成真实的WETH
        uint256 mintAmount
    ) external view returns (uint256 srcAmount, bytes[] memory swapPaths);//外部可读，srcAmount：预估，需要滑点？实际交易的时候需要支付多少；后者算出路径

    function quoteRedeemToToken(//redeem的时候去查询
        address etf,
        address dstToken,
        uint256 burnAmount
    ) external view returns (uint256 dstAmount, bytes[] memory swapPaths);

    function quoteExactOut(//quote输出时？
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view returns (bytes memory path, uint256 amountIn);//路径和输入总量

    function quoteExactIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (bytes memory path, uint256 amountOut);//路径和输出总量
}
