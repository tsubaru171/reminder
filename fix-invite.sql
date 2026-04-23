-- ================================================================
--  FIX: Cho phép tìm workspace bằng invite_code
--  Supabase → SQL Editor → New query → paste → Run
-- ================================================================

-- Xóa policy select cũ
drop policy if exists "ws_select" on workspaces;
drop policy if exists "ws_sel" on workspaces;
drop policy if exists "workspace_select" on workspaces;

-- Policy mới: cho phép select nếu là creator, member, HOẶC biết invite_code
create policy "ws_select" on workspaces for select using (
  auth.uid() = created_by
  or is_workspace_member(id)
  or invite_code is not null  -- ai cũng có thể lookup để join
);
