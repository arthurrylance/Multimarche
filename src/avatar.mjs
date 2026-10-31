export const avatarNames=Object.freeze(['lavender','orange','yellow','green','cyan','blue','violet','red']);
// Account UUIDs are random; hashing the full ID makes the assignment stable on every device.
export function avatarPath(userId,color){
 if(avatarNames.includes(color))return `/avatars/${color}.png`;
 let hash=2166136261;
 for(const char of String(userId??'').toLowerCase())hash=Math.imul(hash^char.charCodeAt(0),16777619)>>>0;
 return `/avatars/${avatarNames[hash%avatarNames.length]}.png`;
}
