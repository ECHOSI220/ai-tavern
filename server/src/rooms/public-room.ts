import type {RoomState} from './types';

/** Invitation-only projection. Never spread internal room/player objects here. */
export function publicRoom(state: RoomState) {
  return {
    roomCode:state.roomCode,roomName:state.roomName,status:state.status,
    maxPlayers:state.maxPlayers,currentPlayers:Object.values(state.players).length,
    aiProviderConnected:state.aiHost.status==='active',
    players:Object.values(state.players).map(p=>({displayName:p.displayName,ready:p.ready,connected:p.connected,isOwner:p.playerId===state.ownerPlayerId})),
  };
}
