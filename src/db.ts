import { createClient } from '@supabase/supabase-js';
// Publishable configuration is intentionally public. RLS protects all group data.
export const supabaseUrl=import.meta.env.VITE_SUPABASE_URL || 'https://vakkbgsooubqpmdekixr.supabase.co';
export const supabasePublishableKey=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_TaBmHyqoiGBiOEpVb0L86g_28xH5B_6';
export const supabase = createClient(supabaseUrl,supabasePublishableKey);
export const usernameEmail = (name:string) => `${name.trim().toLowerCase()}@members.multimarche.invalid`;
