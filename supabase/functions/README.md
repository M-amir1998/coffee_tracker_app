# Edge Functions

Coffee Tracker 1.0 does not use Edge Functions. Every operation, including
account deletion (`public.delete_my_account`), is a SQL function in
`supabase/migrations`, protected by Row Level Security and explicit privileges.

If a future feature needs one (for example sending push notifications), keep
privileged keys in the function's secrets (`supabase secrets set`), never in
the app or in this repository, and add tests for it to CI.
