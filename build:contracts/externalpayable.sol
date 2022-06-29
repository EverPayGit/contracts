receive() external payable {}

 function totalSupply() external view override returns (uint256) {
     return _totalSupply;
 }

 function allowance(address owner_, address spender) external view override returns (uint256){
     return _allowedFragments[owner_][spender];
 }

 function balanceOf(address who) public view override returns (uint256) {
     return _gonBalances[who].div(_gonsPerFragment);
 }

 function checkFeeExempt(address _addr) external view returns (bool) {
     return _isFeeExempt[_addr];
 }

 function checkSwapThreshold() external view returns (uint256) {
     return gonSwapThreshold.div(_gonsPerFragment);
 }

 function shouldRebase() internal view returns (bool) {
     return nextRebase <= block.timestamp;
 }

 function shouldTakeFee(address from, address to) internal view returns (bool) {
     if(_isFeeExempt[from] || _isFeeExempt[to]){
         return false;
     }else if (feesOnNormalTransfers){
         return true;
     }else{
         return (automatedMarketMakerPairs[from] || automatedMarketMakerPairs[to]);
     }
 }

 function shouldSwapBack() internal view returns (bool) {
     return
     !automatedMarketMakerPairs[msg.sender] &&
     !inSwap &&
     swapEnabled &&
     totalBuyFee.add(totalSellFee) > 0 &&
     _gonBalances[address(this)] >= gonSwapThreshold;
 }

 function getCirculatingSupply() public view returns (uint256) {
     return (TOTAL_GONS.sub(_gonBalances[DEAD]).sub(_gonBalances[ZERO])).div(_gonsPerFragment);
 }

 function getLiquidityBacking(uint256 accuracy) public view returns (uint256){
     uint256 liquidityBalance = 0;
     for(uint i = 0; i < _markerPairs.length; i++){
         liquidityBalance.add(balanceOf(_markerPairs[i]).div(10 ** 9));
     }
     return accuracy.mul(liquidityBalance.mul(2)).div(getCirculatingSupply().div(10 ** 9));
 }

 function isOverLiquified(uint256 target, uint256 accuracy) public view returns (bool){
     return getLiquidityBacking(accuracy) > target;
 }

 function manualSync() public {
     for(uint i = 0; i < _markerPairs.length; i++){
         InterfaceLP(_markerPairs[i]).sync();
     }
 }

 function transfer(address to, uint256 value) external override validRecipient(to) returns (bool){
     _transferFrom(msg.sender, to, value);
     return true;
 }

 function _basicTransfer(address from, address to, uint256 amount) internal returns (bool) {
     uint256 gonAmount = amount.mul(_gonsPerFragment);
     _gonBalances[from] = _gonBalances[from].sub(gonAmount);
     _gonBalances[to] = _gonBalances[to].add(gonAmount);

     emit Transfer(from, to, amount);

     return true;
 }

 function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
     bool excludedAccount = _isFeeExempt[sender] || _isFeeExempt[recipient];

     require(initialDistributionFinished || excludedAccount, "Trading not started");


     if (
         automatedMarketMakerPairs[recipient] &&
         !excludedAccount
     ) {
         require(amount <= maxSellTransactionAmount, "Error amount");

         uint blkTime = block.timestamp;

         uint256 onePercent = balanceOf(sender).mul(txfee).div(100); //Should use variable
         require(amount <= onePercent, "ERR: Can't sell more than 1%");

         if( blkTime > tradeData[sender].lastTradeTime + TwentyFourhours) {
             tradeData[sender].lastTradeTime = blkTime;
             tradeData[sender].tradeAmount = amount;
         }
         else if( (blkTime < tradeData[sender].lastTradeTime + TwentyFourhours) && (( blkTime > tradeData[sender].lastTradeTime)) ){
             require(tradeData[sender].tradeAmount + amount <= onePercent, "ERR: Can't sell more than 1% in One day");
             tradeData[sender].tradeAmount = tradeData[sender].tradeAmount + amount;
         }
     }

     if (inSwap) {
         return _basicTransfer(sender, recipient, amount);
     }

     uint256 gonAmount = amount.mul(_gonsPerFragment);

     if (shouldSwapBack()) {
         swapBack();
     }

     _gonBalances[sender] = _gonBalances[sender].sub(gonAmount);

     uint256 gonAmountReceived = shouldTakeFee(sender, recipient) ? takeFee(sender, recipient, gonAmount) : gonAmount;
     _gonBalances[recipient] = _gonBalances[recipient].add(gonAmountReceived);

     emit Transfer(
         sender,
         recipient,
         gonAmountReceived.div(_gonsPerFragment)
     );

     if(shouldRebase() && autoRebase) {
         _rebase();

         if(!automatedMarketMakerPairs[sender] && !automatedMarketMakerPairs[recipient]){
             manualSync();
         }
     }

     return true;
 }

 function transferFrom(address from, address to, uint256 value) external override validRecipient(to) returns (bool) {
     if (_allowedFragments[from][msg.sender] != uint256(-1)) {
         _allowedFragments[from][msg.sender] = _allowedFragments[from][
         msg.sender
         ].sub(value, "Insufficient Allowance");
     }

     _transferFrom(from, to, value);
     return true;
 }

 function _swapAndLiquify(uint256 contractTokenBalance) private {
     uint256 half = contractTokenBalance.div(2);
     uint256 otherHalf = contractTokenBalance.sub(half);

     if(isLiquidityInBnb){
         uint256 initialBalance = address(this).balance;

         _swapTokensForBNB(half, address(this));

         uint256 newBalance = address(this).balance.sub(initialBalance);

         _addLiquidity(otherHalf, newBalance);

         emit SwapAndLiquify(half, newBalance, otherHalf);
     }else{
         uint256 initialBalance = IERC20(busdToken).balanceOf(address(this));

         _swapTokensForBusd(half, address(this));

         uint256 newBalance = IERC20(busdToken).balanceOf(address(this)).sub(initialBalance);

         _addLiquidityBusd(otherHalf, newBalance);

         emit SwapAndLiquifyBusd(half, newBalance, otherHalf);
     }
 }

 function _addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
     router.addLiquidityETH{value: bnbAmount}(
         address(this),
         tokenAmount,
         0,
         0,
         liquidityReceiver,
         block.timestamp
     );
 }
 function _addLiquidityBusd(uint256 tokenAmount, uint256 busdAmount) private {
     router.addLiquidity(
         address(this),
         busdToken,
         tokenAmount,
         busdAmount,
         0,
         0,
         liquidityReceiver,
         block.timestamp
     );
 }

 function _swapTokensForBNB(uint256 tokenAmount, address receiver) private {
     address[] memory path = new address[](2);
     path[0] = address(this);
     path[1] = router.WETH();

     router.swapExactTokensForETHSupportingFeeOnTransferTokens(
         tokenAmount,
         0,
         path,
         receiver,
         block.timestamp
     );
 }
 function _swapTokensForBusd(uint256 tokenAmount, address receiver) private {
     address[] memory path = new address[](3);
     path[0] = address(this);
     path[1] = router.WETH();
     path[2] = busdToken;

     router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
         tokenAmount,
         0,
         path,
         receiver,
         block.timestamp
     );
 }

 function swapBack() internal swapping {
     uint256 realTotalFee = totalBuyFee.add(totalSellFee);

     uint256 dynamicLiquidityFee = isOverLiquified(targetLiquidity, targetLiquidityDenominator) ? 0 : liquidityFee;
     uint256 contractTokenBalance = _gonBalances[address(this)].div(_gonsPerFragment);

     uint256 amountToLiquify = contractTokenBalance.mul(dynamicLiquidityFee.mul(2)).div(realTotalFee);
     uint256 amountToRFV = contractTokenBalance.mul(buyFeeRFV.mul(2).add(sellFeeRFVAdded)).div(realTotalFee);
     uint256 amountToTreasury = contractTokenBalance.sub(amountToLiquify).sub(amountToRFV);

     if(amountToLiquify > 0){
         _swapAndLiquify(amountToLiquify);
     }

     if(amountToRFV > 0){
         _swapTokensForBusd(amountToRFV, riskFreeValueReceiver);
     }

     if(amountToTreasury > 0){
         _swapTokensForBNB(amountToTreasury, treasuryReceiver);
     }

     emit SwapBack(contractTokenBalance, amountToLiquify, amountToRFV, amountToTreasury);
 }

 function takeFee(address sender, address recipient, uint256 gonAmount) internal returns (uint256){
     uint256 _realFee = totalBuyFee;
     if(automatedMarketMakerPairs[recipient]) _realFee = totalSellFee;

     uint256 feeAmount = gonAmount.mul(_realFee).div(feeDenominator);

     _gonBalances[address(this)] = _gonBalances[address(this)].add(feeAmount);
     emit Transfer(sender, address(this), feeAmount.div(_gonsPerFragment));

     return gonAmount.sub(feeAmount);
 }

 function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool){
     uint256 oldValue = _allowedFragments[msg.sender][spender];
     if (subtractedValue >= oldValue) {
         _allowedFragments[msg.sender][spender] = 0;
     } else {
         _allowedFragments[msg.sender][spender] = oldValue.sub(
             subtractedValue
         );
     }
     emit Approval(
         msg.sender,
         spender,
         _allowedFragments[msg.sender][spender]
     );
     return true;
 }

 function increaseAllowance(address spender, uint256 addedValue) external returns (bool){
     _allowedFragments[msg.sender][spender] = _allowedFragments[msg.sender][
     spender
     ].add(addedValue);
     emit Approval(
         msg.sender,
         spender,
         _allowedFragments[msg.sender][spender]
     );
     return true;
 }

 function approve(address spender, uint256 value) external override returns (bool){
     _allowedFragments[msg.sender][spender] = value;
     emit Approval(msg.sender, spender, value);
     return true;
 }

 function _rebase() private {
     if(!inSwap) {
         uint256 circulatingSupply = getCirculatingSupply();
         int256 supplyDelta = int256(circulatingSupply.mul(rewardYield).div(rewardYieldDenominator));

         coreRebase(supplyDelta);
     }
 }

 function coreRebase(int256 supplyDelta) private returns (uint256) {
     uint256 epoch = block.timestamp;

     if (supplyDelta == 0) {
         emit LogRebase(epoch, _totalSupply);
         return _totalSupply;
     }

     if (supplyDelta < 0) {
         _totalSupply = _totalSupply.sub(uint256(-supplyDelta));
     } else {
         _totalSupply = _totalSupply.add(uint256(supplyDelta));
     }

     if (_totalSupply > MAX_SUPPLY) {
         _totalSupply = MAX_SUPPLY;
     }

     _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

     nextRebase = epoch + rebaseFrequency;

     emit LogRebase(epoch, _totalSupply);
     return _totalSupply;
 }

 function manualRebase() external onlyWhitelisted{
     require(!inSwap, "Try again");
     require(nextRebase <= block.timestamp, "Not in time");

     uint256 circulatingSupply = getCirculatingSupply();
     int256 supplyDelta = int256(circulatingSupply.mul(rewardYield).div(rewardYieldDenominator));

     coreRebase(supplyDelta);
     manualSync();
 }

 function setAutomatedMarketMakerPair(address _pair, bool _value) public onlyOwner {
     require(automatedMarketMakerPairs[_pair] != _value, "Value already set");

     automatedMarketMakerPairs[_pair] = _value;

     if(_value){
         _markerPairs.push(_pair);
     }else{
         require(_markerPairs.length > 1, "Required 1 pair");
         for (uint256 i = 0; i < _markerPairs.length; i++) {
             if (_markerPairs[i] == _pair) {
                 _markerPairs[i] = _markerPairs[_markerPairs.length - 1];
                 _markerPairs.pop();
                 break;
             }
         }
     }

     emit SetAutomatedMarketMakerPair(_pair, _value);
 }

 function setInitialDistributionFinished(bool _value) external onlyOwner {
     require(initialDistributionFinished != _value, "Not changed");
     initialDistributionFinished = _value;
 }

 function setFeeExempt(address _addr, bool _value) external onlyOwner {
     require(_isFeeExempt[_addr] != _value, "Not changed");
     _isFeeExempt[_addr] = _value;
 }

 function setTxFee(uint _addr) external onlyOwner {
     txfee = _addr;
 }

 function setTwentyFourhours(uint256 _time) external onlyOwner {
     TwentyFourhours = _time;
 }

 function setTargetLiquidity(uint256 target, uint256 accuracy) external onlyOwner {
     targetLiquidity = target;
     targetLiquidityDenominator = accuracy;
 }

 function setSwapBackSettings(bool _enabled, uint256 _num, uint256 _denom) external onlyOwner {
     swapEnabled = _enabled;
     gonSwapThreshold = TOTAL_GONS.div(_denom).mul(_num);
 }

 function setFeeReceivers(address _liquidityReceiver, address _treasuryReceiver, address _riskFreeValueReceiver) external onlyOwner {
     liquidityReceiver = _liquidityReceiver;
     treasuryReceiver = _treasuryReceiver;
     riskFreeValueReceiver = _riskFreeValueReceiver;
 }

 function setFees(uint256 _liquidityFee, uint256 _riskFreeValue, uint256 _treasuryFee, uint256 _sellFeeTreasuryAdded, uint256 _sellFeeRFVAdded, uint256 _feeDenominator) external onlyOwner {
     require(
         _liquidityFee <= MAX_FEE_RATE &&
         _riskFreeValue <= MAX_FEE_RATE &&
         _treasuryFee <= MAX_FEE_RATE &&
         _sellFeeTreasuryAdded <= MAX_FEE_RATE &&
         _sellFeeRFVAdded <= MAX_FEE_RATE,
         "wrong"
     );

     liquidityFee = _liquidityFee;
     buyFeeRFV = _riskFreeValue;
     treasuryFee = _treasuryFee;
     sellFeeTreasuryAdded = _sellFeeTreasuryAdded;
     sellFeeRFVAdded = _sellFeeRFVAdded;
     totalBuyFee = liquidityFee.add(treasuryFee).add(buyFeeRFV);
     totalSellFee = totalBuyFee.add(sellFeeTreasuryAdded).add(sellFeeRFVAdded);
     feeDenominator = _feeDenominator;
     require(totalBuyFee < feeDenominator / 4);
 }

 function clearStuckBalance(address _receiver) external onlyOwner {
     uint256 balance = address(this).balance;
     payable(_receiver).transfer(balance);
 }

 function rescueToken(address tokenAddress, uint256 tokens) external onlyOwner returns (bool success){
     return ERC20Detailed(tokenAddress).transfer(msg.sender, tokens);
 }

 function setAutoRebase(bool _autoRebase) external onlyOwner {
     require(autoRebase != _autoRebase, "Not changed");
     autoRebase = _autoRebase;
 }

 function setRebaseFrequency(uint256 _rebaseFrequency) external onlyOwner {
     require(_rebaseFrequency <= MAX_REBASE_FREQUENCY, "Too high");
     rebaseFrequency = _rebaseFrequency;
 }

 function setRewardYield(uint256 _rewardYield, uint256 _rewardYieldDenominator) external onlyOwner {
     rewardYield = _rewardYield;
     rewardYieldDenominator = _rewardYieldDenominator;
 }

 function setFeesOnNormalTransfers(bool _enabled) external onlyOwner {
     require(feesOnNormalTransfers != _enabled, "Not changed");
     feesOnNormalTransfers = _enabled;
 }

 function setIsLiquidityInBnb(bool _value) external onlyOwner {
     require(isLiquidityInBnb != _value, "Not changed");
     isLiquidityInBnb = _value;
 }

 function setNextRebase(uint256 _nextRebase) external onlyOwner {
     nextRebase = _nextRebase;
 }

 function setMaxSellTransaction(uint256 _maxTxn) external onlyOwner {
     maxSellTransactionAmount = _maxTxn;
 }

 event SwapBack(uint256 contractTokenBalance,uint256 amountToLiquify,uint256 amountToRFV,uint256 amountToTreasury);
 event SwapAndLiquify(uint256 tokensSwapped, uint256 bnbReceived, uint256 tokensIntoLiqudity);
 event SwapAndLiquifyBusd(uint256 tokensSwapped, uint256 busdReceived, uint256 tokensIntoLiqudity);
 event LogRebase(uint256 indexed epoch, uint256 totalSupply);
 event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
}
