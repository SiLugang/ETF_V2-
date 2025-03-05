// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IETFQuoter} from "./interfaces/IETFQuoter.sol";
import {IETFv1} from "./interfaces/IETFv1.sol";
import {IUniswapV3Quoter} from "./interfaces/IUniswapV3Quoter.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {IERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";

contract ETFQuoter is IETFQuoter {//主要功能：价格查询/流动性查询/交易报价/路径优化
    using FullMath for uint256;

    uint24[4] public fees;//遍历的数组，和uniV3一样的费率
    address public immutable weth;//作为路径的两个中间代币？
    address public immutable usdc;//作为路径的两个中间代币？

    IUniswapV3Quoter public immutable uniswapV3Quoter;//会用到V3的Quoter

    constructor(address uniswapV3Quoter_, address weth_, address usdc_) {//函数，进行初始化
        uniswapV3Quoter = IUniswapV3Quoter(uniswapV3Quoter_);
        weth = weth_;
        usdc = usdc_;
        fees = [100, 500, 3000, 10000];//费率分别是，和下面公式有关系？
    }

    function quoteInvestWithToken(//实现逻辑：invest时
        address etf,
        address srcToken,
        uint256 mintAmount
    )
        external
        view
        override
        returns (uint256 srcAmount, bytes[] memory swapPaths)
    {
        address[] memory tokens = IETFv1(etf).getTokens();//拿到tokens
        uint256[] memory tokenAmounts = IETFv1(etf).getInvestTokenAmounts(//拿到tokenamount，
            mintAmount
        );

        swapPaths = new bytes[](tokens.length);//swappath和数组长度一样，给它初始化
        for (uint256 i = 0; i < tokens.length; i++) {//遍历
            if (srcToken == tokens[i]) {//两个代币一样的话，和tokeni一样
                srcAmount += tokenAmounts[i];//首先累加上去
                swapPaths[i] = bytes.concat(//组装路径
                    bytes20(srcToken),//路径，20字节的
                    bytes3(fees[0]),//fee随便取一个fees[0]，3字节
                    bytes20(srcToken)//20字节的代币
                );
            } else {//两个代币不一样的话
                (bytes memory path, uint256 amountIn) = quoteExactOut(//用quoteExactOut获取路径和amountin，函数实现在98行
                    srcToken,
                    tokens[i],
                    tokenAmounts[i]
                );
                srcAmount += amountIn;//把得出的amountin累加到srcAmount
                swapPaths[i] = path;//路径存储到swappath
            }
        }
    }

    function quoteRedeemToToken(//实现逻辑：redeem时
        address etf,
        address dstToken,
        uint256 burnAmount
    )
        external
        view
        override
        returns (uint256 dstAmount, bytes[] memory swapPaths)
    {
        address[] memory tokens = IETFv1(etf).getTokens();
        uint256[] memory tokenAmounts = IETFv1(etf).getRedeemTokenAmounts(
            burnAmount
        );

        swapPaths = new bytes[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {//遍历：
            if (dstToken == tokens[i]) {
                dstAmount += tokenAmounts[i];//路径
                swapPaths[i] = bytes.concat(
                    bytes20(dstToken),
                    bytes3(fees[0]),
                    bytes20(dstToken)
                );
            } else {
                (bytes memory path, uint256 amountOut) = quoteExactIn(//函数实现在121行
                    tokens[i],
                    dstToken,
                    tokenAmounts[i]
                );
                dstAmount += amountOut;//把dstamount赋值
                swapPaths[i] = path;//路径赋值
            }
        }
    }

    function quoteExactOut(//output需要放在前面，input需要放在后面
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) public view returns (bytes memory path, uint256 amountIn) {//
        bytes[] memory allPaths = getAllPaths(tokenOut, tokenIn);//output需要放在前面，input需要放在后面。拿到了所有的路径。函数实现在142行
        for (uint256 i = 0; i < allPaths.length; i++) {//循环遍历所有路径，并且都查一下输出的amountin是多少，把最小损耗的fee算出来
            try//try：捕获处理外部调用错误，避免整个交易回滚。
                uniswapV3Quoter.quoteExactOutput(allPaths[i], amountOut)//传入遍历路径
            returns (//四个返回
                uint256 amountIn_,
                uint160[] memory,
                uint32[] memory,
                uint256
            ) {
                if (amountIn_ > 0 && (amountIn == 0 || amountIn_ < amountIn)) {//当amountIn_大于0的时候，amountin为0且In_小于In的时候：
                    amountIn = amountIn_;//更新amountIn替换，找出最小损耗的amountin
                    path = allPaths[i];//更新path替换，找出最小损耗amountin的path
                }
            } catch {}//catch没有就跳过
        }
    }

    function quoteExactIn(//通过指定的amountIn，找出amountOut
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view returns (bytes memory path, uint256 amountOut) {
        bytes[] memory allPaths = getAllPaths(tokenIn, tokenOut);//和quoteExactOut不同，先tokenin，再tokenout
        for (uint256 i = 0; i < allPaths.length; i++) {//找出最优路径
            try uniswapV3Quoter.quoteExactInput(allPaths[i], amountIn) returns (//找出最优路径
                uint256 amountOut_,
                uint160[] memory,
                uint32[] memory,
                uint256
            ) {
                if (amountOut_ > amountOut) {//输出需要越多越好
                    amountOut = amountOut_;//大于时重新赋值
                    path = allPaths[i];//重新赋值路径
                }
            } catch {}
        }
    }

    function getAllPaths(//A是最开头的token，B是兑换结果的token。获得所有路径的function
        address tokenA,
        address tokenB
    ) public view returns (bytes[] memory paths) {返回路径的数组
        // 计算路径数量
        uint totalPaths = fees.length + (fees.length * fees.length * 2);//？四个费率四个路径？为什么是4个？组成路径有这么多和公式什么关系
        paths = new bytes[](totalPaths);//路径

        uint256 index = 0;//索引

        // 1. 生成直接路径：tokenA -> fee -> tokenB
        for (uint256 i = 0; i < fees.length; i++) {//遍历fees
            paths[index] = bytes.concat(//tokenA -> fee -> tokenB
                bytes20(tokenA),
                bytes3(fees[i]),
                bytes20(tokenB)
            );
            index++;//记录下来
        }

        // 2. 生成中间代币路径：tokenA -> fee1 -> intermediary -> fee2 -> tokenB
        address[2] memory intermediaries = [weth, usdc];//中间代币有这两种
        for (uint256 i = 0; i < intermediaries.length; i++) {//遍历中间代币
            for (uint256 j = 0; j < fees.length; j++) {//遍历fee1？
                for (uint256 k = 0; k < fees.length; k++) {//遍历fee2？
                    paths[index] = bytes.concat(
                        bytes20(tokenA),
                        bytes3(fees[j]),
                        bytes20(intermediaries[i]),
                        bytes3(fees[k]),
                        bytes20(tokenB)
                    );
                    index++;
                }
            }
        }
    }
}
