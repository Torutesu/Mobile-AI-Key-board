import { z } from "zod";
const opaque = (prefix: string) => z.string().regex(new RegExp(`^${prefix}_[A-Za-z0-9_-]{16,128}$`));
export const GrantId = opaque("grant");
export type GrantId = z.infer<typeof GrantId>;
