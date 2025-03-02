// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IETFv1} from "./IETFv1.sol";

interface IETFv2 is IETFv1 {//继承了IETFv1
    error InvalidSwapPath(bytes swapPath);
    error InvalidArrayLength();
    error OverSlippage();
    error SafeTransferETHFailed();

    event InvestedWithETH(address to, uint256 mintAmount, uint256 paidAmount);//申购函数继承
    event InvestedWithToken(
        address indexed srcToken,
        address to,
        uint256 mintAmount,
        uint256 totalPaid
    );
    event RedeemedToETH(address to, uint256 burnAmount, uint256 receivedAmount);//赎回函数继承
    event RedeemedToToken(
        address indexed dstToken,
        address to,
        uint256 burnAmount,
        uint256 receivedAmount
    );

    function investWithETH(//功能1.1：ETH支付，ETH需单独定义
        address to,//ETF接收的地址
        uint256 mintAmount,//申购mint数量
        bytes[] memory swapPaths//关键函数swapPaths需要传过来，用于ETF自动兑换其他token；路径的数组：
    ) external payable;

    function investWithToken(//功能1.2：用其他ERC20的token去支付
        address srcToken,//除ETH以外其他代币的地址
        address to,
        uint256 mintAmount,
        uint256 maxSrcTokenAmount,//增加了滑点的配置，考虑到手续费和滑点的损耗？
        bytes[] memory swapPaths//关键函数swapPaths需要传过来，用于该token自动兑换其他token；路径的数组：
    ) external;

    function redeemToETH(//单独ETH赎回
        address to,//赎回的地址
        uint256 burnAmount,//burn的数量
        uint256 minETHAmount,//赎回的token总量
        bytes[] memory swapPaths//函数作用是兑换路径的数组
    ) external;

    function redeemToToken(//单独其他代币赎回
        address dstToken,//指定的token
        address to,//赎回的地址？用户地址？
        uint256 burnAmount,//burn的数量
        uint256 minDstTokenAmount,//赎回的token总量
        bytes[] memory swapPaths//函数作用是兑换路径的数组
    ) external;

    function swapRouter() external view returns (address);//v3用到

    function weth() external view returns (address);//真WETH，和ETH互换的
}
