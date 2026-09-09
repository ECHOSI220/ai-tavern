// In-process workerd integration-test entry only. Never deploy this entry: it
// intentionally bypasses the outer Worker auth to exercise the real DO runtime.
import type { Env } from '../src/env';
export { GameRoomDurableObject } from '../src/durable/game-room';
export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return env.GAME_ROOMS.get(env.GAME_ROOMS.idFromName('runtime-test')).fetch(request);
  },
};
