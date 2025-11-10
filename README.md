# AI-Powered Support & Resistance EA for MT5

## Overview

This Expert Advisor (EA) automatically identifies Support and Resistance (S/R) levels using advanced algorithms and executes trades based on bounce and breakout strategies. The EA combines price action analysis, multi-timeframe confirmation, candlestick patterns, and volume analysis to identify high-probability trading opportunities.

## Key Features

### 1. **Intelligent S/R Detection**
- **Swing High/Low Algorithm**: Identifies significant price reversals
- **Multi-Timeframe Analysis**: Confirms levels across H1, H4, and D1 timeframes
- **Level Clustering**: Merges nearby levels to reduce noise
- **Strength Classification**: Rates levels as Weak, Medium, or Strong based on touches and confirmations
- **Dynamic Updates**: Removes broken levels and updates active ones in real-time

### 2. **Trading Strategies**

#### Bounce Trading (Recommended)
- Buys at Support levels when price bounces
- Sells at Resistance levels when price rejects
- Uses candlestick confirmation (pin bars, engulfing patterns)
- Optional RSI filter for oversold/overbought conditions

#### Breakout Trading (Optional)
- Buys when resistance breaks decisively upward
- Sells when support breaks decisively downward
- Requires volume confirmation
- Prevents duplicate trades on same breakout

#### Range Trading (Future Feature)
- Trades within identified ranges
- Buys at support, sells at resistance
- Exits when range breaks

### 3. **Advanced Filters**

- **Candlestick Patterns**: Pin bars, bullish/bearish engulfing
- **Volume Analysis**: Ensures high volume at entry points
- **RSI Confirmation**: Optional overbought/oversold filter
- **Minimum Distance**: Prevents entries too far from S/R levels

### 4. **Comprehensive Risk Management**

- **Position Sizing**:
  - Fixed lot size
  - Risk-based sizing (% of account balance per trade)
- **Stop Loss**: Placed beyond S/R level with buffer
- **Take Profit**: Based on reward:risk ratio (default 2:1)
- **Trailing Stop**: Locks in profits as trade moves favorably
- **Max Daily Loss**: Stops trading when daily loss limit reached
- **Max Open Trades**: Limits concurrent positions

### 5. **Visual Interface**

- **Chart Display**: Shows all S/R levels with color coding
  - Blue lines = Support
  - Red lines = Resistance
  - Line thickness = Level strength
- **Level Labels**: Display strength and touch count
- **Chart Comment**: Real-time stats (balance, equity, open positions, strongest levels)

## Installation

1. **Copy the EA file** (`AI_SR_EA.mq5`) to your MT5 `Experts` folder:
   - `C:\Users\[YourName]\AppData\Roaming\MetaQuotes\Terminal\[BrokerID]\MQL5\Experts\`

2. **Compile the EA** in MetaEditor (F7) or it will auto-compile when you first use it

3. **Drag and drop** the EA onto any chart in MT5

4. **Configure settings** in the inputs dialog (see Configuration section below)

5. **Enable AutoTrading** (click the AutoTrading button in MT5 toolbar)

## Configuration Guide

### S/R Detection Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| SwingLookback | 100 | Number of bars to scan for swing points |
| MinTouches | 2 | Minimum touches required to confirm a level |
| ClusterTolerance | 10 | Pips tolerance to merge nearby levels |
| UseMultiTimeframe | true | Enable multi-timeframe confirmation |
| TF1 | H1 | Primary timeframe for analysis |
| TF2 | H4 | Secondary timeframe for confirmation |
| TF3 | D1 | Tertiary timeframe for confirmation |

**Recommendations:**
- For scalping: SwingLookback = 50, TF1 = M15, TF2 = H1, TF3 = H4
- For day trading: SwingLookback = 100, TF1 = H1, TF2 = H4, TF3 = D1 (default)
- For swing trading: SwingLookback = 200, TF1 = H4, TF2 = D1, TF3 = W1

### Trading Strategy Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| EnableBounceTrading | true | Trade bounces from S/R levels |
| EnableBreakoutTrading | false | Trade breakouts through S/R levels |
| EnableRangeTrading | false | Trade ranges (future feature) |
| MinLevelStrength | 2 | Minimum strength (1=Weak, 2=Medium, 3=Strong) |

**Recommendations:**
- Start with bounce trading only
- Only enable breakout trading after backtesting
- Use MinLevelStrength = 2 for conservative trading
- Use MinLevelStrength = 1 for aggressive trading (more signals)

### Entry Filters

| Parameter | Default | Description |
|-----------|---------|-------------|
| UseVolumeFilter | true | Require high volume for entry |
| UseCandlePatterns | true | Require candlestick pattern confirmation |
| UseIndicatorConfirmation | false | Use RSI filter (optional) |
| RSI_Period | 14 | RSI calculation period |
| RSI_Overbought | 70 | RSI overbought level |
| RSI_Oversold | 30 | RSI oversold level |
| MinDistanceFromLevel | 5 | Minimum pips from S/R to enter |

**Recommendations:**
- Keep UseVolumeFilter = true for quality entries
- Keep UseCandlePatterns = true for confirmation
- Enable RSI only if you understand it (can reduce trade frequency)
- MinDistanceFromLevel prevents late entries

### Risk Management Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| RiskPercent | 1.0 | Risk per trade as % of balance |
| FixedLotSize | 0.1 | Fixed lot (if RiskPercent = 0) |
| StopLossBuffer | 10 | Pips buffer beyond S/R level for SL |
| RewardRiskRatio | 2.0 | TP distance as multiple of SL distance |
| UseTrailingStop | true | Enable trailing stop |
| TrailingStopStart | 20 | Pips profit before trailing begins |
| TrailingStopDistance | 15 | Trailing stop distance in pips |

**Recommendations:**
- Conservative: RiskPercent = 0.5%, RewardRiskRatio = 3.0
- Moderate: RiskPercent = 1.0%, RewardRiskRatio = 2.0 (default)
- Aggressive: RiskPercent = 2.0%, RewardRiskRatio = 1.5
- Always use RiskPercent for proper money management
- StopLossBuffer = 10-20 pips depending on volatility

### Position Management

| Parameter | Default | Description |
|-----------|---------|-------------|
| MaxOpenTrades | 3 | Maximum concurrent positions |
| MaxDailyLoss | 5.0 | Maximum daily loss as % of balance |
| MagicNumber | 123456 | Unique identifier for EA trades |
| TradeComment | AI_SR_EA | Comment on all trades |

**Recommendations:**
- MaxOpenTrades = 1-3 for conservative approach
- MaxOpenTrades = 5-10 for aggressive approach
- MaxDailyLoss = 3-5% to protect capital
- Change MagicNumber if running multiple EAs

### Chart Display

| Parameter | Default | Description |
|-----------|---------|-------------|
| ShowSRLevels | true | Display S/R lines on chart |
| ShowTradingZones | true | Display trading zones |
| SupportColor | Blue | Color for support lines |
| ResistanceColor | Red | Color for resistance lines |
| LevelStyle | Solid | Line style for levels |

## Trading Logic

### Bounce Trading Process

1. **Level Detection**: EA scans for swing highs/lows
2. **Confirmation**: Checks multiple timeframes for agreement
3. **Strength Rating**: Assigns weak/medium/strong rating
4. **Price Approach**: Waits for price to approach S/R level
5. **Pattern Check**: Looks for bullish/bearish rejection candles
6. **Volume Check**: Ensures above-average volume
7. **Entry**: Opens trade with SL beyond level, TP at R:R ratio
8. **Management**: Trails stop as profit increases

### Breakout Trading Process

1. **Level Monitoring**: Watches established S/R levels
2. **Breakout Detection**: Price closes beyond level with buffer
3. **Volume Confirmation**: High volume on breakout
4. **Entry**: Opens trade in breakout direction
5. **SL Placement**: Stops below/above broken level
6. **Management**: Trails to next S/R level

## Backtesting Recommendations

### Strategy Tester Settings

1. Open **Strategy Tester** (Ctrl+R)
2. Select **AI_SR_EA.ex5**
3. Choose symbol (EURUSD, GBPUSD, XAUUSD recommended)
4. Select timeframe (H1 recommended)
5. Set date range (minimum 2 years)
6. Set model: **Every tick based on real ticks**
7. Enable **Visual mode** to see trades

### Test Parameters

**Conservative Setup:**
```
RiskPercent = 0.5
MinLevelStrength = 2
EnableBounceTrading = true
EnableBreakoutTrading = false
RewardRiskRatio = 3.0
MaxOpenTrades = 1
```

**Moderate Setup (Default):**
```
RiskPercent = 1.0
MinLevelStrength = 2
EnableBounceTrading = true
EnableBreakoutTrading = false
RewardRiskRatio = 2.0
MaxOpenTrades = 3
```

**Aggressive Setup:**
```
RiskPercent = 2.0
MinLevelStrength = 1
EnableBounceTrading = true
EnableBreakoutTrading = true
RewardRiskRatio = 1.5
MaxOpenTrades = 5
```

### Performance Metrics to Monitor

- **Win Rate**: Target 50-60%
- **Profit Factor**: Target > 1.5
- **Max Drawdown**: Should be < 20%
- **Recovery Factor**: Target > 3
- **Sharpe Ratio**: Target > 1

## Live Trading Setup

### Demo Account First (Mandatory)

1. Run EA on **demo account** for minimum 1 month
2. Monitor daily for issues
3. Verify settings work for your broker
4. Check spread impact on performance
5. Ensure no errors in logs

### Going Live

1. Start with **minimum risk** (RiskPercent = 0.5%)
2. Use **low leverage** (1:30 or less)
3. Start with **one symbol** (EURUSD or GBPUSD)
4. Set **MaxOpenTrades = 1** initially
5. Monitor **every day** for first week
6. Gradually increase risk after proven results

### Recommended Symbols

**Forex Pairs:**
- EURUSD (tight spreads, good liquidity)
- GBPUSD (good volatility, clear S/R levels)
- USDJPY (respects S/R levels well)
- AUDUSD (clear trends and ranges)

**Metals:**
- XAUUSD (Gold - excellent S/R respect)
- XAGUSD (Silver - high volatility)

**Indices:**
- US30 (Dow Jones)
- NAS100 (Nasdaq)
- SPX500 (S&P 500)

## Troubleshooting

### No Trades Opening

**Check:**
1. AutoTrading enabled?
2. Market closed? (wait for market open)
3. MaxDailyLoss reached? (check account comment)
4. MaxOpenTrades reached? (close some positions)
5. MinLevelStrength too high? (lower to 1)
6. No S/R levels detected? (lower MinTouches to 2)

### Too Many Trades

**Solutions:**
1. Increase MinLevelStrength to 3
2. Enable only BounceTrading
3. Increase MinDistanceFromLevel to 10-15
4. Reduce MaxOpenTrades
5. Enable RSI filter

### Losses Occurring

**Review:**
1. Is spread too high? (check broker)
2. Are you using proper risk %? (should be ≤ 2%)
3. Did you backtest first?
4. Is StopLossBuffer too tight? (increase to 15-20)
5. Is market too choppy? (avoid low volatility periods)

### EA Not Displaying Levels

**Check:**
1. ShowSRLevels = true?
2. Chart has enough history loaded?
3. MinTouches not too high? (should be 2)
4. Check expert log for errors

## Performance Optimization

### For Higher Win Rate
- Increase MinLevelStrength to 3
- Enable UseCandlePatterns
- Enable UseVolumeFilter
- Increase RewardRiskRatio to 3.0
- Trade only major pairs (EURUSD, GBPUSD)

### For More Trade Frequency
- Decrease MinLevelStrength to 1
- Increase MaxOpenTrades to 5
- Enable both BounceTrading and BreakoutTrading
- Reduce MinDistanceFromLevel to 3
- Use multiple timeframes

### For Better Risk Management
- Set RiskPercent = 0.5-1.0%
- Set MaxDailyLoss = 3-5%
- Set MaxOpenTrades = 1-3
- Use RewardRiskRatio = 2.5-3.0
- Enable UseTrailingStop

## Version History

### Version 1.0 (Current)
- Initial release
- Swing high/low S/R detection
- Multi-timeframe confirmation
- Bounce trading strategy
- Breakout trading strategy
- Candlestick pattern recognition
- Volume filter
- RSI confirmation (optional)
- Risk-based position sizing
- Trailing stop
- Max daily loss protection
- Visual S/R display on chart

### Planned Features (Future Versions)

**Version 1.1:**
- Range trading strategy
- Additional candlestick patterns (doji, hammer, shooting star)
- Fibonacci level integration
- News filter (avoid trading during high-impact news)

**Version 1.2:**
- AI/ML adaptive learning
- Success rate tracking per level
- Optimal entry distance learning
- Adaptive R:R ratio based on market conditions

**Version 2.0:**
- Pattern recognition (double top/bottom, H&S, triangles)
- Session-specific trading (London, NY, Asian)
- Market regime detection (trending vs ranging)
- Advanced money management (Martingale, Anti-Martingale)

## Support & Disclaimer

### Important Notice

**This EA is for educational and research purposes. Trading involves substantial risk of loss. Past performance does not guarantee future results.**

- Always test on demo account first
- Never risk more than you can afford to lose
- Use proper risk management (≤ 2% per trade)
- Monitor your account regularly
- Understand all settings before going live

### Getting Help

For issues or questions:
1. Check this README thoroughly
2. Review MT5 Expert log (Tools > Options > Expert Advisors)
3. Verify all settings match recommendations
4. Test on demo account first

## License

Copyright 2025, AI Trading Systems. All rights reserved.

---

**Good luck and trade responsibly! 📈**
