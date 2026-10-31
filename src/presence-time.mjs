export function lastBetLabel(timestamp,now=Date.now()){
 if(!timestamp)return 'No bets yet';
 const at=Date.parse(timestamp);if(!Number.isFinite(at))return 'Last bet unavailable';
 const seconds=Math.max(0,Math.floor((now-at)/1000));
 if(seconds<60)return 'Last bet just now';
 const [amount,unit]=seconds<3600?[Math.floor(seconds/60),'minute']:seconds<86400?[Math.floor(seconds/3600),'hour']:[Math.floor(seconds/86400),'day'];
 return `Last bet ${amount} ${unit}${amount===1?'':'s'} ago`;
}
