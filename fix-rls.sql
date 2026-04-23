-- ================================================================
--  FIX RLS POLICIES — Chạy file này trong Supabase SQL Editor
--  Supabase → SQL Editor → New query → paste → Run
-- ================================================================

-- Xóa policies cũ bị conflict
drop policy if exists "ws_sel" on workspaces;
drop policy if exists "ws_select" on workspaces;
drop policy if exists "ws_ins" on workspaces;
drop policy if exists "ws_insert" on workspaces;
drop policy if exists "ws_update" on workspaces;
drop policy if exists "workspace_select" on workspaces;
drop policy if exists "workspace_insert" on workspaces;
drop policy if exists "workspace_update" on workspaces;
drop policy if exists "wm_sel" on workspace_members;
drop policy if exists "wm_select" on workspace_members;
drop policy if exists "wm_ins" on workspace_members;
drop policy if exists "wm_insert" on workspace_members;
drop policy if exists "wm_del" on workspace_members;
drop policy if exists "wm_delete" on workspace_members;

-- Workspaces: creator có thể select workspace của mình (kể cả khi chưa là member)
create policy "ws_select" on workspaces for select using (
  auth.uid() = created_by
  or is_workspace_member(id)
);

-- RPC: lookup workspace by invite code (for join flow)
create or replace function workspace_by_invite(p_invite_code text)
returns setof workspaces
language sql
security definer
set search_path = public
as $$
  select *
  from workspaces
  where invite_code = p_invite_code
  limit 1;
$$;

grant execute on function workspace_by_invite(text) to authenticated;

create policy "ws_insert" on workspaces for insert with check (
  auth.uid() = created_by
);

create policy "ws_update" on workspaces for update using (
  auth.uid() = created_by
);

-- Workspace members: cho phép insert nếu là chính mình hoặc creator của workspace
create policy "wm_select" on workspace_members for select using (
  is_workspace_member(workspace_id)
  or auth.uid() = user_id
);

create policy "wm_insert" on workspace_members for insert with check (
  auth.uid() = user_id
  or exists (
    select 1 from workspaces w
    where w.id = workspace_id and w.created_by = auth.uid()
  )
  or is_workspace_member(workspace_id)
);

create policy "wm_delete" on workspace_members for delete using (
  auth.uid() = user_id
  or exists (
    select 1
    from workspace_members me
    where me.workspace_id = workspace_members.workspace_id
      and me.user_id = auth.uid()
      and me.role = 'admin'
      and workspace_members.role <> 'admin'
  )
);

-- ================================================================
-- FIX RLS + COLUMN UPGRADES — Chạy trong Supabase SQL Editor
-- Supabase → SQL Editor → New query → paste → Run
--
-- Mục tiêu:
--  - Thêm role cho teamspace_members (admin/mod/member)
--  - Thêm repeat_weekdays cho reminders
--  - Nới RLS cho repeat “update-same” (creator reset done cho assignees)
-- ================================================================

-- ------------------------------------------------
-- 1) Columns / constraints
-- ------------------------------------------------

alter table teamspace_members
  add column if not exists role text not null default 'member';

alter table teamspace_members
  drop constraint if exists teamspace_members_role_check;

alter table teamspace_members
  add constraint teamspace_members_role_check
  check (role in ('admin','mod','member'));

alter table reminders
  add column if not exists repeat_weekdays int[];

-- ------------------------------------------------
-- 2) Teamspace member roles (admin/mod/member)
-- ------------------------------------------------

drop policy if exists "tsm_sel" on teamspace_members;
drop policy if exists "tsm_ins" on teamspace_members;
drop policy if exists "tsm_del" on teamspace_members;
drop policy if exists "tsm_upd" on teamspace_members;

create policy "tsm_sel" on teamspace_members for select using (
  exists (
    select 1
    from teamspaces t
    where t.id = teamspace_members.teamspace_id
      and is_workspace_member(t.workspace_id)
  )
);

create policy "tsm_ins" on teamspace_members for insert with check (
  -- Bootstrap: teamspace creator có thể tự add chính mình (admin)
  -- và add người khác ban đầu với role = 'member'
  (
    exists (
      select 1
      from teamspaces t
      where t.id = teamspace_members.teamspace_id
        and t.created_by = auth.uid()
    )
    and (
      (teamspace_members.user_id = auth.uid() and teamspace_members.role = 'admin')
      or (teamspace_members.user_id <> auth.uid() and teamspace_members.role = 'member')
    )
  )
  or
  -- Ongoing management: admin/mod trong teamspace mới được insert
  (
    exists (
      select 1
      from teamspace_members me
      where me.teamspace_id = teamspace_members.teamspace_id
        and me.user_id = auth.uid()
        and (
          me.role = 'admin'
          or (me.role = 'mod' and teamspace_members.role = 'member')
        )
    )
  )
);

create policy "tsm_del" on teamspace_members for delete using (
  exists (
    select 1
    from teamspace_members me
    where me.teamspace_id = teamspace_members.teamspace_id
      and me.user_id = auth.uid()
      and (
        me.role = 'admin'
        or (me.role = 'mod' and teamspace_members.role <> 'admin')
      )
  )
);

create policy "tsm_upd" on teamspace_members for update using (
  exists (
    select 1
    from teamspace_members me
    where me.teamspace_id = teamspace_members.teamspace_id
      and me.user_id = auth.uid()
      and me.role = 'admin'
  )
);

-- ------------------------------------------------
-- 3) Reminder repeat: allow creator to reset assignments
-- ------------------------------------------------

drop policy if exists "asgn_upd" on reminder_assignments;

create policy "asgn_upd" on reminder_assignments for update using (
  auth.uid() = user_id
  or exists (
    select 1
    from reminders r
    where r.id = reminder_id
      and r.created_by = auth.uid()
  )
);
