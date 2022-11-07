// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./IERC20USDT.sol";
import "./IUniswapV2Pair.sol";
import "./IBettingPair.sol";

contract LeveragePool is Ownable {
    using SafeMath for uint256;

    mapping(address => uint256) _ethPool;   // deposited ETH amounts per accounts
    mapping(address => uint256) _usdtPool;  // deposited USDT amounts per accounts
    mapping(address => uint256) _usdcPool;  // deposited USDC amounts per accounts
    mapping(address => uint256) _shibPool;  // deposited SHIB amounts per accounts
    mapping(address => uint256) _dogePool;  // deposited DOGE amounts per accounts

    IUniswapV2Pair _usdtEth = IUniswapV2Pair(0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852);   // Uniswap USDT/ETH pair
    IUniswapV2Pair _usdcEth = IUniswapV2Pair(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);   // Uniswap USDC/ETH pair
    IUniswapV2Pair _shibEth = IUniswapV2Pair(0x811beEd0119b4AfCE20D2583EB608C6F7AF1954f);   // Uniswap SHIB/ETH pair
    IUniswapV2Pair _dogeEth = IUniswapV2Pair(0xc0067d751FB1172DBAb1FA003eFe214EE8f419b6);   // Uniswap DOGE/ETH pair

    uint256 ETH_DECIMAL = 18;   // ETH decimal
    uint256 USDT_DECIMAL = 6;   // USDT decimal
    uint256 USDC_DECIMAL = 6;   // USDC decimal
    uint256 SHIB_DECIMAL = 18;  // SHIB decimal
    uint256 DOGE_DECIMAL = 8;   // DOGE decimal

    constructor() {}

    /*
    * @Get deposited user balance
    */
    function getUserLPBalance(address account) external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (_ethPool[account], _usdtPool[account], _usdcPool[account], _shibPool[account], _dogePool[account]);
    }

    /*
    * @Get ETH/USDT price from uniswap v2 pool
    */
    function getUsdtPrice() internal view returns (uint256) {
        uint256 reserve0;
        uint256 reserve1;
        uint32 timestamp;
        (reserve0, reserve1, timestamp) = _usdtEth.getReserves();

        uint256 r0NoDecimal = reserve0.div(10 ** ETH_DECIMAL);
        uint256 r1NoDecimal = reserve1.div(10 ** USDT_DECIMAL);

        uint256 price = r1NoDecimal.div(r0NoDecimal);

        return price;
    }

    /*
    * @Get ETH/USDC price from uniswap v2 pool
    */
    function getUsdcPrice() internal view returns (uint256) {
        uint256 reserve0;
        uint256 reserve1;
        uint32 timestamp;
        (reserve0, reserve1, timestamp) = _usdcEth.getReserves();

        uint256 r0NoDecimal = reserve0.div(10 ** USDC_DECIMAL);
        uint256 r1NoDecimal = reserve1.div(10 ** ETH_DECIMAL);

        uint256 price = r0NoDecimal.div(r1NoDecimal);

        return price;
    }

    /*
    * @Get ETH/SHIB price from uniswap v2 pool
    */
    function getShibPrice() internal view returns (uint256) {
        uint256 reserve0;
        uint256 reserve1;
        uint32 timestamp;
        (reserve0, reserve1, timestamp) = _shibEth.getReserves();

        uint256 r0NoDecimal = reserve0.div(10 ** SHIB_DECIMAL);
        uint256 r1NoDecimal = reserve1.div(10 ** ETH_DECIMAL);

        uint256 price = r0NoDecimal.div(r1NoDecimal);

        return price;
    }

    /*
    * @Get ETH/DOGE price from uniswap v2 pool
    */
    function getDogePrice() internal view returns (uint256) {
        uint256 reserve0;
        uint256 reserve1;
        uint32 timestamp;
        (reserve0, reserve1, timestamp) = _dogeEth.getReserves();

        uint256 r0NoDecimal = reserve0.div(10 ** DOGE_DECIMAL);
        uint256 r1NoDecimal = reserve1.div(10 ** ETH_DECIMAL);

        uint256 price = r0NoDecimal.div(r1NoDecimal);

        return price;
    }

    /*
    * @Function for depositing ETH.
    * @This function should be separated from other deposit functions because this should be payable.
    */
    function depositEth(address player, uint256 amount) external onlyOwner {
        require(amount >= 0.01 ether, "Minimum deposit amount is 0.01");

        _ethPool[player] += amount;
    }

    /*
    * @Function for depositing other ERC20 tokens with no tax
    * @This function should be separated from deposit Eth function because this is not payable function.
    */
    function depositErc20(address player, IBettingPair.LPTOKENTYPE token, uint256 amount) external onlyOwner {
        address player_ = player;

        if (token == IBettingPair.LPTOKENTYPE.USDT) {
            _usdtPool[player_] += amount;
        }
        else if (token == IBettingPair.LPTOKENTYPE.USDC) {
            _usdcPool[player_] += amount;
        }
        else if (token == IBettingPair.LPTOKENTYPE.SHIB){
            _shibPool[player_] += amount;
        }
        else if (token == IBettingPair.LPTOKENTYPE.DOGE) {
            _dogePool[player_] += amount;
        }
    }

    /*
    * @Function for withdrawing tokens.
    */
    function withdraw(address player, IBettingPair.LPTOKENTYPE token, uint256 amount) external onlyOwner {
        address player_ = player;

        if (token == IBettingPair.LPTOKENTYPE.ETH) {
            _ethPool[player_] -= amount;
        } else if (token == IBettingPair.LPTOKENTYPE.USDT) {
            _usdtPool[player_] -= amount;
        } else if (token == IBettingPair.LPTOKENTYPE.USDC) {
            _usdcPool[player_] -= amount;
        } else if (token == IBettingPair.LPTOKENTYPE.SHIB) {
            _shibPool[player_] -= amount;
        } else if (token == IBettingPair.LPTOKENTYPE.DOGE) {
            _dogePool[player_] -= amount;
        }
    }

    /*
    * @Function to lock tokens for collateral.
    */
    function lock(address player, uint256 ethAmount, uint256 usdtAmount, uint256 usdcAmount, uint256 shibAmount, uint256 dogeAmount) external onlyOwner {
        _ethPool[player] -= ethAmount;
        _usdtPool[player] -= usdtAmount;
        _usdcPool[player] -= usdcAmount;
        _shibPool[player] -= shibAmount;
        _dogePool[player] -= dogeAmount;
    }

    /*
    * @Function to unlock tokens which were used for collateral.
    */
    function unlock(address player, uint256 ethAmount, uint256 usdtAmount, uint256 usdcAmount, uint256 shibAmount, uint256 dogeAmount) external onlyOwner {
        _ethPool[player] += ethAmount;
        _usdtPool[player] += usdtAmount;
        _usdcPool[player] += usdcAmount;
        _shibPool[player] += shibAmount;
        _dogePool[player] += dogeAmount;
    }

    /*
    * @Function for withdrawing tokens from this contract by owner.
    */
    function withdrawFromContract(address owner, IBettingPair.LPTOKENTYPE token, uint256 amount) external onlyOwner {
        require(amount > 0, "Withdraw amount should be bigger than 0");
        if (token == IBettingPair.LPTOKENTYPE.ETH) {
            if (_ethPool[owner] >= amount) {
                _ethPool[owner] -= amount;
            } else {
                _ethPool[owner] = 0;
            }
        } else if (token == IBettingPair.LPTOKENTYPE.USDT) {
            if (_usdtPool[owner] >= amount) {
                _usdtPool[owner] -= amount;
            } else {
                _usdtPool[owner] = 0;
            }
        } else if (token == IBettingPair.LPTOKENTYPE.USDC) {
            if (_usdcPool[owner] >= amount) {
                _usdcPool[owner] -= amount;
            } else {
                _usdcPool[owner] = 0;
            }
        } else if (token == IBettingPair.LPTOKENTYPE.SHIB) {
            if (_shibPool[owner] >= amount) {
                _shibPool[owner] -= amount;    
            } else {
                _shibPool[owner] = 0;
            }
        } else if (token == IBettingPair.LPTOKENTYPE.DOGE) {
            if (_dogePool[owner] >= amount) {
                _dogePool[owner] -= amount;
            } else {
                _dogePool[owner] = 0;
            }
        }
    }

    /*
    * @Function to get player's total leverage pool balance in ETH.
    */
    function getPlayerLPBalanceInEth(address player) external view returns (uint256) {
        uint256 usdtPrice = getUsdtPrice();
        uint256 usdcPrice = getUsdcPrice();
        uint256 shibPrice = getShibPrice();
        uint256 dogePrice = getDogePrice();

        return  _ethPool[player] +
                uint256(10**12).mul(_usdtPool[player]).div(usdtPrice) +
                uint256(10**12).mul(_usdcPool[player]).div(usdcPrice) +
                _shibPool[player].div(shibPrice) +
                uint256(10**10).mul(_dogePool[player]).div(dogePrice);
    }

    /*
    * @Function to calculate pool token amounts equivalent to multiplier.
    * @Calculating starts from eth pool. If there are sufficient tokens in eth pool, the eth pool will be reduced.
    *   In other case, it checks the usdt pool. And next usdc pool.
    *   It continues this process until it reaches the same amount as input ether amount.
    */
    function calcLockTokenAmountsAsCollateral(address player, uint256 etherAmount) external view returns (uint256, uint256, uint256, uint256, uint256) {
        address _player = player;
        uint256 rAmount = etherAmount;
        // Each token balance in eth.
        uint256 ethFromUsdt = uint256(10**12).mul(_usdtPool[_player]).div(getUsdtPrice());
        uint256 ethFromUsdc = uint256(10**12).mul(_usdcPool[_player]).div(getUsdcPrice());
        uint256 ethFromShib = _shibPool[_player].div(getShibPrice());
        uint256 ethFromDoge = uint256(10**10).mul(_dogePool[_player]).div(getDogePrice());

        // If player has enough eth pool balance, the collateral will be set from eth pool.
        if (_ethPool[_player] >= rAmount) {
            return (rAmount, 0, 0, 0, 0);
        }
        // Otherwise, all ethers in eth pool will be converted to collateral and the remaining collateral amounts will be
        // set from usdt pool.
        rAmount -= _ethPool[_player];
        
        if (ethFromUsdt >= rAmount) {
            return (_ethPool[_player], _usdtPool[_player].mul(rAmount).div(ethFromUsdt), 0, 0, 0);
        }
        rAmount -= ethFromUsdt;
        
        if (ethFromUsdc >= rAmount) {
            return (_ethPool[_player], _usdtPool[_player], _usdcPool[_player].mul(rAmount).div(ethFromUsdc), 0, 0);
        }
        rAmount -= ethFromUsdc;

        if (ethFromShib >= rAmount) {
            return (_ethPool[_player], _usdtPool[_player], _usdcPool[_player], _shibPool[_player].mul(rAmount).div(ethFromShib), 0);
        }
        rAmount -= ethFromShib;

        require(ethFromDoge >= rAmount, "You don't have enough collateral token amounts");
        return (_ethPool[_player], _usdtPool[_player], _usdcPool[_player], _shibPool[_player], _dogePool[_player].mul(rAmount).div(ethFromDoge));
    }
}