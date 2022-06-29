IDEXRouter public router;
 address public pair;

 uint256 public liquidityFee = value;
 uint256 public treasuryFee = value;
 uint256 public buyFeeRFV = value;
 uint256 public sellFeeTreasuryAdded = value;
 uint256 public sellFeeRFVAdded = value;
 uint256 public totalBuyFee = liquidityFee.add(treasuryFee).add(buyFeeRFV);
 uint256 public totalSellFee = totalBuyFee.add(sellFeeTreasuryAdded).add(sellFeeRFVAdded);
 uint256 public feeDenominator = fee denominator value;

 uint256 targetLiquidity = value;
 uint256 targetLiquidityDenominator = denominator value;

 bool inSwap;
 uint256 public txfee = fee value;

 modifier swapping() {
     inSwap = true;
     _;
     inSwap = false;
 }

 struct user {
     uint256 firstBuy;
     uint256 lastTradeTime;
     uint256 tradeAmount;
 }

 uint256 public TwentyFourhours = value;

 mapping(address => user) public tradeData;

 modifier validRecipient(address to) {
     require(to != address(0x0));
     _;
 }

 uint256 private _totalSupply;
 uint256 private _gonsPerFragment;
 uint256 private gonSwapThreshold = (TOTAL_GONS * 10) / 10000;

 mapping(address => uint256) private _gonBalances;
 mapping(address => mapping(address => uint256)) private _allowedFragments;

 constructor() ERC20Detailed("LockPay", "LOCKPAY", uint8(DECIMALS)) {
     router = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
     pair = IDEXFactory(router.factory()).createPair(address(this), router.WETH());
     address pairBusd = IDEXFactory(router.factory()).createPair(address(this), busdToken);

     _allowedFragments[address(this)][address(router)] = uint256(-1);
     _allowedFragments[address(this)][pair] = uint256(-1);
     _allowedFragments[address(this)][address(this)] = uint256(-1);
     _allowedFragments[address(this)][pairBusd] = uint256(-1);

     setAutomatedMarketMakerPair(pair, true);
     setAutomatedMarketMakerPair(pairBusd, true);

     _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
     _gonBalances[msg.sender] = TOTAL_GONS;
     _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

     _isFeeExempt[treasuryReceiver] = true;
     _isFeeExempt[riskFreeValueReceiver] = true;
     _isFeeExempt[address(this)] = true;
     _isFeeExempt[msg.sender] = true;

     IERC20(busdToken).approve(address(router), uint256(-1));
     IERC20(busdToken).approve(address(pairBusd), uint256(-1));
     IERC20(busdToken).approve(address(this), uint256(-1));

     emit Transfer(address(0x0), msg.sender, _totalSupply);
 }


// all written valiues need to be change to your independant values. 
