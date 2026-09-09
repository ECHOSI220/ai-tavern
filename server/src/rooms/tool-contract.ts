import { z } from 'zod';
const id = z.string().min(1).max(128);
export const toolSchemas = {
  move_character: z.object({ characterId: id, locationId: id }).strict(),
  damage_character: z.object({ characterId: id, amount: z.number().int().min(0).max(100) }).strict(),
  advance_time: z.object({ minutes: z.number().int().min(0).max(1440) }).strict(),
  roll_dice: z.object({ checkId: id, formula: z.string().regex(/^\d{1,2}d\d{1,4}([+-]\d{1,4})?$/), visibility: z.enum(['public', 'player', 'gm']), playerId: id.optional(), reason: z.string().max(200) }).strict(),
};
export const aiTools = Object.entries(toolSchemas).map(([name, schema]) => ({
  type: 'function', function: { name, description: '请求服务器执行并验证规则操作。以工具返回结果为准。', parameters: z.toJSONSchema(schema) },
}));
export function validateTool(name: string, args: unknown): Record<string, unknown> {
  const schema = toolSchemas[name as keyof typeof toolSchemas];
  if (!schema) throw new Error(`不支持的规则工具：${name}`);
  return schema.parse(args);
}
