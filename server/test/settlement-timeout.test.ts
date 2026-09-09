import {describe,it,expect} from 'vitest';
import {RoomEngine,aiRequestTimeoutMs,aiSettlementTimeoutMs} from '../src/rooms/room-engine';
import {envelope} from '../src/protocol/schema';

async function active(){
  const {engine}=await RoomEngine.create({roomId:crypto.randomUUID(),roomCode:'ABC234',roomName:'test',campaignId:'test',rulePackId:'simple_trpg',ownerUserId:'owner',ownerName:'Owner',maxPlayers:2,allowPlayerPrivateChat:false,settings:{}});
  const owner=engine.state.ownerPlayerId;
  const send=(type:Parameters<typeof envelope>[0],payload:Record<string,unknown>)=>engine.handle(owner,envelope(type,engine.state.roomId,payload,engine.state.revision,0,{commandId:crypto.randomUUID()}));
  send('hostRequested',{providerPlayerId:owner});send('hostAccepted',{modelId:'fake'});send('playerReady',{ready:true});send('gameStarted',{});send('turnActionConfirm',{content:'Investigate'});engine.finalizeTurnCountdown(Date.now()+5001);
  return {engine,owner,send};
}
describe('AI settlement deadlines',()=>{
  it('continues reasoning tools without publishing reasoning and preserves provider context',async()=>{
    const {engine,send}=await active();
    send('aiResponse',{requestId:engine.state.aiHost.requestId,response:{content:'private thought',usedReasoningFallback:true,reasoningContent:'private thought',toolCalls:[{id:'reason-clock',type:'function',function:{name:'advance_time',arguments:'{"minutes":5}'}}]}});
    const assistant=engine.state.aiHost.messages!.find(m=>m.role==='assistant');
    expect(assistant).toMatchObject({content:null,reasoning_content:'private thought'});
    expect(engine.state.campaignTime).toBe(5);
    expect(JSON.stringify(engine.state.session.chatHistory)).not.toContain('private thought');
    send('aiResponse',{requestId:engine.state.aiHost.requestId,response:{content:'Time passes.'}});
    expect(engine.state.currentTurn!.roundNumber).toBe(2);
  });
  it('expires a stalled request despite live heartbeats and keeps confirmed actions',async()=>{
    const {engine,send}=await active();
    const requestId=engine.state.aiHost.requestId, actions=structuredClone(engine.state.currentTurn!.playerActions);
    const deadline=engine.aiDeadline!;send('hostHeartbeat',{});
    expect(engine.expireAIRequest(deadline-1).changed).toBe(false);
    expect(engine.expireAIRequest(deadline).events[0]!.payload.code).toBe('AI_TIMEOUT');
    expect(engine.state.currentTurn!.playerActions).toEqual(actions);
    expect(engine.state.aiHost.requestId).toBeUndefined();
    expect(engine.recoverStalledTurn().changed).toBe(false);
    expect(()=>send('aiResponse',{requestId,response:{content:'late'}})).toThrow();
    send('retryAction',{});
    expect(engine.state.aiHost.requestId).not.toBe(requestId);
    expect(engine.state.aiHost.lastError).toBeUndefined();
    send('aiResponse',{requestId:engine.state.aiHost.requestId,response:{content:'Recovered'}});
    expect(engine.state.currentTurn!.roundNumber).toBe(2);
  });
  it('preserves committed tool results when retrying and bounds the whole tool chain',async()=>{
    const {engine,send}=await active();
    engine.state.aiHost.settlementStartedAt=new Date(Date.now()-aiSettlementTimeoutMs+1000).toISOString();
    send('aiResponse',{requestId:engine.state.aiHost.requestId,response:{toolCalls:[{id:'clock',type:'function',function:{name:'advance_time',arguments:'{"minutes":5}'}}]}});
    const messages=structuredClone(engine.state.aiHost.messages);
    expect(engine.aiDeadline! - Date.now()).toBeLessThan(1500);
    engine.expireAIRequest(engine.aiDeadline!);
    send('retryAction',{});
    expect(engine.state.aiHost.messages).toEqual(messages);
    expect(engine.state.campaignTime).toBe(5);
    send('aiResponse',{requestId:engine.state.aiHost.requestId,response:{content:'Done'}});
    expect(engine.state.campaignTime).toBe(5);
  });
  it('adds bounded deadlines to old in-flight snapshots',async()=>{
    const {engine}=await active();delete engine.state.aiHost.requestStartedAt;delete engine.state.aiHost.settlementStartedAt;
    expect(engine.recoverStalledTurn().changed).toBe(true);
    expect(engine.aiDeadline!).toBeLessThanOrEqual(Date.now()+aiRequestTimeoutMs);
  });
  it('reports provider failure without automatic retry loops or leaking raw provider errors',async()=>{
    const {engine,send}=await active();
    const response=send('aiResponse',{requestId:engine.state.aiHost.requestId,error:'secret-api-key'});
    expect(response.events[0]!.payload.code).toBe('AI_PROVIDER_FAILED');
    expect(JSON.stringify(response)).not.toContain('secret-api-key');
    expect(engine.recoverStalledTurn().changed).toBe(false);
  });
});
