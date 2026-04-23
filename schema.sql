-- RemindBoard Supabase Schema
-- Paste vào SQL Editor trong Supabase dashboard → Run

create extension if not exists "uuid-ossp";

create table if not exists workspaces (
  id          uuid primary key default uuid_generate_v4(),
  name        text not null,
  icon        text default '🏢',
  invite_code text unique not null default substr(md5(random()::text), 1, 10),
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz default now()
);

create table if not exists workspace_members (
  id           uuid primary key default uuid_generate_v4(),
  workspace_id uuid references workspaces(id) on delete cascade,
  user_id      uuid references auth.users(id) on delete cascade,
  display_name text not null,
  email        text not null,
  role         text default 'member' check (role in ('admin','member')),
  joined_at    timestamptz default now(),
  unique (workspace_id, user_id)
);

create table if not exists teamspaces (
  id           uuid primary key default uuid_generate_v4(),
  workspace_id uuid references workspaces(id) on delete cascade,
  name         text not null,
  icon         text default '👥',
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz default now()
);

create table if not exists teamspace_members (
  id           uuid primary key default uuid_generate_v4(),
  teamspace_id uuid references teamspaces(id) on delete cascade,
  user_id      uuid references auth.users(id) on delete cascade,
  role         text not null default 'member' check (role in ('admin','mod','member')),
  added_at     timestamptz default now(),
  unique (teamspace_id, user_id)
);

create table if not exists reminders (
  id           uuid primary key default uuid_generate_v4(),
  workspace_id uuid references workspaces(id) on delete cascade,
  teamspace_id uuid references teamspaces(id) on delete set null,
  title        text not null,
  description  text,
  due_at       timestamptz not null,
  priority     text default 'normal' check (priority in ('low','normal','high')),
  repeat_weekdays int[] ,
  created_by   uuid references auth.users(id) on delete set null,
  is_done      boolean default false,
  created_at   timestamptz default now()
);

create table if not exists reminder_assignments (
  id          uuid primary key default uuid_generate_v4(),
  reminder_id uuid references reminders(id) on delete cascade,
  user_id     uuid references auth.users(id) on delete cascade,
  is_done     boolean default false,
  done_at     timestamptz,
  unique (reminder_id, user_id)
);

create table if not exists notifications (
  id           uuid primary key default uuid_generate_v4(),
  workspace_id uuid references workspaces(id) on delete cascade,
  user_id      uuid references auth.users(id) on delete cascade,
  type         text not null,
  title        text not null,
  icon         text default '🔔',
  reminder_id  uuid references reminders(id) on delete cascade,
  is_read      boolean default false,
  created_at   timestamptz default now()
);

-- Row Level Security
alter table workspaces           enable row level security;
alter table workspace_members    enable row level security;
alter table teamspaces           enable row level security;
alter table teamspace_members    enable row level security;
alter table reminders            enable row level security;
alter table reminder_assignments enable row level security;
alter table notifications        enable row level security;

-- Helper function
create or replace function is_workspace_member(ws_id uuid)
returns boolean language sql security definer as $$
  select exists (select 1 from workspace_members where workspace_id=ws_id and user_id=auth.uid());
$$;

-- Policies (skip if already exist)
do $$ begin
  create policy "ws_sel" on workspaces for select using (is_workspace_member(id));
  create policy "ws_ins" on workspaces for insert with check (auth.uid()=created_by);
  create policy "wm_sel" on workspace_members for select using (is_workspace_member(workspace_id));
  create policy "wm_ins" on workspace_members for insert with check (auth.uid()=user_id or is_workspace_member(workspace_id));
  create policy "wm_del" on workspace_members for delete using (
    auth.uid() = user_id
    or (
      exists (
        select 1
        from workspace_members me
        where me.workspace_id = workspace_members.workspace_id
          and me.user_id = auth.uid()
          and me.role = 'admin'
          and workspace_members.role <> 'admin'
      )
    )
  );
  create policy "ts_sel" on teamspaces for select using (is_workspace_member(workspace_id));
  create policy "ts_ins" on teamspaces for insert with check (is_workspace_member(workspace_id));
  create policy "ts_upd" on teamspaces for update using (is_workspace_member(workspace_id));
  create policy "ts_del" on teamspaces for delete using (auth.uid()=created_by);
  create policy "tsm_sel" on teamspace_members for select using (exists(select 1 from teamspaces t where t.id=teamspace_id and is_workspace_member(t.workspace_id)));
  create policy "tsm_ins" on teamspace_members for insert with check (
    -- Bootstrap: teamspace creator có thể thêm chính mình (admin)
    -- và thêm người khác ban đầu với role 'member'.
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
    -- Ongoing management: chỉ admin/mod trong teamspace mới được insert.
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
  create policy "rem_sel" on reminders for select using (is_workspace_member(workspace_id));
  create policy "rem_ins" on reminders for insert with check (is_workspace_member(workspace_id));
  create policy "rem_upd" on reminders for update using (is_workspace_member(workspace_id));
  create policy "rem_del" on reminders for delete using (auth.uid()=created_by);
  create policy "asgn_sel" on reminder_assignments for select using (exists(select 1 from reminders r where r.id=reminder_id and is_workspace_member(r.workspace_id)));
  create policy "asgn_ins" on reminder_assignments for insert with check (exists(select 1 from reminders r where r.id=reminder_id and is_workspace_member(r.workspace_id)));
  create policy "asgn_upd" on reminder_assignments for update using (
    auth.uid() = user_id
    or exists(select 1 from reminders r where r.id = reminder_id and r.created_by = auth.uid())
  );
  create policy "notif_sel" on notifications for select using (auth.uid()=user_id);
  create policy "notif_ins" on notifications for insert with check (is_workspace_member(workspace_id));
  create policy "notif_upd" on notifications for update using (auth.uid()=user_id);
exception when duplicate_object then null;
end $$;

-- Enable Realtime
alter publication supabase_realtime add table reminders;
alter publication supabase_realtime add table reminder_assignments;
alter publication supabase_realtime add table notifications;
alter publication supabase_realtime add table workspace_members;
