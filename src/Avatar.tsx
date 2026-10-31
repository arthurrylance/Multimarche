import {createContext,useContext} from 'react';
import type {ReactNode} from 'react';
import type {Profile} from './types';
import {avatarPath} from './avatar.mjs';
const AvatarColors=createContext<Record<string,string|null|undefined>>({});
export function AvatarProvider({profiles,children}:{profiles:Profile[];children:ReactNode}){
 return <AvatarColors.Provider value={Object.fromEntries(profiles.map(p=>[p.id,p.avatar_color]))}>{children}</AvatarColors.Provider>;
}
export default function Avatar({userId,size=32,color}:{userId:string;size?:number;color?:string|null}){
 const colors=useContext(AvatarColors);
 return <img className="profile-picture" src={avatarPath(userId,color??colors[userId])} alt="" width={size} height={size} decoding="async"/>;
}
