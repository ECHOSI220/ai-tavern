import {it,expect} from 'vitest';
import {RoomEngine} from '../src/rooms/room-engine';
import {publicRoom} from '../src/rooms/public-room';
it('invitation projection contains only public allowlisted fields',async()=>{
 const {engine}=await RoomEngine.create({roomId:crypto.randomUUID(),roomCode:'ABC234',roomName:'测试',campaignId:'campaign-secret',rulePackId:'simple_trpg',ownerUserId:'user-secret',ownerName:'房主',maxPlayers:6,allowPlayerPrivateChat:true,settings:{secret:'private-setting'}});
 const json=JSON.stringify(publicRoom(engine.state));
 for(const value of ['user-secret','campaign-secret','private-setting','sessionId','reconnectToken','messages','session','currentTurn','permissions'])expect(json).not.toContain(value);
 expect(Object.keys(publicRoom(engine.state)).sort()).toEqual(['roomCode','roomName','status','maxPlayers','currentPlayers','aiProviderConnected','players'].sort());
 expect(Object.keys(publicRoom(engine.state).players[0]!).sort()).toEqual(['displayName','ready','connected','isOwner'].sort());
});
