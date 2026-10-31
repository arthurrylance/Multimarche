export function automaticPrice(levels,action,fallback=.5){
 const prices=levels.filter(l=>Number(l.size)>0).map(l=>Number(l.price)).filter(p=>Number.isFinite(p)&&p>=.0001&&p<=.9999);
 const best=prices.length?(action==='buy'?Math.min(...prices):Math.max(...prices)):fallback;
 return Math.min(.9999,Math.max(.0001,Math.round((Number.isFinite(best)?best:.5)*10000)/10000));
}
export function quantityForCredits(credits,price){
 const value=Number(credits),cents=Math.round(value*100),ticks=Math.round(price*10000);
 if(!Number.isFinite(value)||value<=0||Math.abs(value*100-cents)>1e-6||!Number.isSafeInteger(cents)||!Number.isFinite(price)||ticks<1||ticks>9999)return 0;
 const quantityTicks=BigInt(cents)*1000000n/BigInt(ticks);
 if(quantityTicks>10000000000n)return 0;
 return Number(quantityTicks)/10000;
}
export function sellFraction(available,percent){
 if(!Number.isFinite(available)||available<=0||!Number.isFinite(percent)||percent<=0||percent>100)return 0;
 return Math.floor(Math.round(available*10000)*percent/100)/10000;
}
