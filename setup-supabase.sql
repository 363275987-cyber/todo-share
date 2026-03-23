-- ============================================================
-- 待办事项多人协同 - Supabase 建表脚本
-- 请在 Supabase Dashboard → SQL Editor 中执行
-- ============================================================

-- 1. 任务完成状态表（核心表）
-- 每条任务的完成状态、备注、操作者
CREATE TABLE IF NOT EXISTS todo_states (
  todo_id INT PRIMARY KEY,
  completed BOOLEAN DEFAULT false,
  note TEXT DEFAULT '',
  completed_by TEXT DEFAULT '',
  completed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. 操作日志表
-- 记录每次状态变更，用于追溯
CREATE TABLE IF NOT EXISTS todo_logs (
  id BIGSERIAL PRIMARY KEY,
  todo_id INT NOT NULL,
  action TEXT NOT NULL,          -- 'complete', 'uncomplete', 'note'
  user_identity TEXT NOT NULL,   -- '老王', '凯哥', '阿超'
  detail TEXT DEFAULT '',        -- 备注内容或描述
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. 行级安全策略（RLS）
-- 所有人可读写（简单场景，不需要登录认证）
ALTER TABLE todo_states ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read todo_states" ON todo_states FOR SELECT USING (true);
CREATE POLICY "Public write todo_states" ON todo_states FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE todo_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read todo_logs" ON todo_logs FOR SELECT USING (true);
CREATE POLICY "Public write todo_logs" ON todo_logs FOR ALL USING (true) WITH CHECK (true);

-- 4. 启用 Realtime（默认 PostgreSQL replication 已开启）
ALTER PUBLICATION supabase_realtime ADD TABLE todo_states;
ALTER PUBLICATION supabase_realtime ADD TABLE todo_logs;

-- ============================================================
-- 完成！前端会自动连接并开始工作。
-- ============================================================
