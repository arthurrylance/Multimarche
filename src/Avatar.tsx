import {avatarPath} from './avatar.mjs';
export default function Avatar({userId,size=32}:{userId:string;size?:number}){
 return <img className="profile-picture" src={avatarPath(userId)} alt="" width={size} height={size} decoding="async"/>;
}
