import type { Env } from "../env";
import { ServerError } from "../utils/errors";
import type { RoomState } from "../rooms/types";
import { z } from 'zod';

export const campaignInputSchema = z.object({
  title: z.string().trim().min(1).max(120), description: z.string().max(8000).default(''),
  template_id: z.string().max(128).optional(), rule_pack_id: z.string().max(128).default('simple_trpg'),
  rule_pack_version: z.number().int().positive().default(1),
  world_snapshot_version: z.number().int().positive().default(1),
  visibility: z.enum(['private', 'invite_only', 'friends', 'public']).default('private'),
  state: z.record(z.string(), z.unknown()),
}).strict();

interface RoomMetadata { room_id: string; room_code: string; status: string }

export class SupabaseAdmin {
  private readonly base: string;
  private readonly headers: HeadersInit;
  constructor(private readonly env: Env) {
    this.base = `${env.SUPABASE_URL.replace(/\/$/, "")}/rest/v1`;
    this.headers = { apikey: env.SUPABASE_SERVICE_ROLE_KEY, authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, "content-type": "application/json" };
  }
  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const response = await fetch(`${this.base}${path}`, { ...init, signal: AbortSignal.timeout(15_000), headers: { ...this.headers, ...init.headers } });
    if (!response.ok) throw new ServerError("DATABASE_ERROR", `数据库操作失败 (${response.status})`, 502);
    const body = await response.text();
    return body.trim() ? JSON.parse(body) as T : undefined as T;
  }
  async createRoom(state: RoomState): Promise<void> {
    await this.request("/room_metadata", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ room_id: state.roomId, room_code: state.roomCode, owner_user_id: state.ownerUserId, campaign_id: state.campaignId, room_name: state.roomName, status: state.status, max_players: state.maxPlayers, server_region: "auto", last_revision: state.revision }) });
  }
  async shareDownload(id: string, userId?: string): Promise<{url:string;checksum:string;version:number}> {
    const rows=await this.request<{author_user_id:string;visibility:string;status:string;current_version:number}[]>(`/shared_contents?id=eq.${id}&select=author_user_id,visibility,status,current_version&limit=1`);
    const content=rows[0];
    if(!content || !(content.author_user_id===userId || (content.status==='PUBLISHED' && ['PUBLIC','UNLISTED'].includes(content.visibility)))) throw new ServerError('CONTENT_NOT_FOUND','内容不存在或无权访问',404);
    const versions=await this.request<{file_path:string;checksum:string;version:number}[]>(`/shared_content_versions?content_id=eq.${id}&version=eq.${content.current_version}&select=file_path,checksum,version&limit=1`);
    const version=versions[0];
    if(!version || version.file_path!==`${content.author_user_id}/${id}/${version.version}.json`) throw new ServerError('VERSION_UNAVAILABLE','版本不可下载',404);
    const base=this.env.SUPABASE_URL.replace(/\/$/,'');
    const response=await fetch(`${base}/storage/v1/object/sign/shared-content/${version.file_path}`,{method:'POST',headers:this.headers,body:JSON.stringify({expiresIn:60}),signal:AbortSignal.timeout(10000)});
    if(!response.ok) throw new ServerError('DOWNLOAD_UNAVAILABLE','暂时无法下载，请稍后重试',502);
    const signed=await response.json<{signedURL:string}>();
    if(!signed.signedURL.startsWith('/object/sign/'))throw new ServerError('INVALID_STORAGE_RESPONSE','下载响应无效',502);
    return {url:`${base}/storage/v1${signed.signedURL}`,checksum:version.checksum,version:version.version};
  }
  async findRoomByCode(code: string): Promise<RoomMetadata | null> {
    const rows = await this.request<RoomMetadata[]>(`/room_metadata?room_code=eq.${encodeURIComponent(code)}&status=not.in.(closed,finished)&select=room_id,room_code,status&limit=1`);
    return rows?.[0] ?? null;
  }
  async updateRoom(state: RoomState): Promise<void> {
    await this.request(`/room_metadata?room_id=eq.${state.roomId}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ status: state.status, current_players: Object.keys(state.players).length, last_revision: state.revision, updated_at: new Date().toISOString() }) });
  }
  async checkpoint(state: RoomState): Promise<void> {
    await this.request('/rpc/save_multiplayer_checkpoint', { method: 'POST', body: JSON.stringify({ target_room: state.roomId, target_campaign: state.campaignId, target_revision: state.revision, target_snapshot: state }) });
  }
  async listCampaigns(userId: string): Promise<unknown[]> {
    return this.request(`/campaigns?owner_id=eq.${encodeURIComponent(userId)}&select=id,title,description,created_at,updated_at&order=updated_at.desc&limit=100`);
  }
  async getCampaign(userId: string, id: string): Promise<unknown> {
    const rows = await this.request<unknown[]>(`/campaigns?owner_id=eq.${encodeURIComponent(userId)}&id=eq.${encodeURIComponent(id)}&select=*&limit=1`);
    return rows[0] ?? null;
  }
  async saveCampaign(userId: string, input: Record<string, unknown>): Promise<unknown> {
    const rows = await this.request<unknown[]>("/campaigns?select=id,title,description,created_at,updated_at", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ ...campaignInputSchema.parse(input), owner_id: userId }) });
    return rows?.[0] ?? null;
  }
}
