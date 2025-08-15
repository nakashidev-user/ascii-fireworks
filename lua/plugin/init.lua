local M = {}

local default_config = {
	enable = true,
	events = { "BufWritePost" }, -- 反応するイベント
	duration_ms = 700, -- アニメ総時間
	frame_interval_ms = 80, -- フレーム間隔
	min_bytes_for_big = 4096, -- これ以上の書き込みで派手に
	max_bursts = 5, -- 同時に弾ける花火の最大数
	mode = "virt", -- "virt"（仮想テキスト）/ 将来 "float" に拡張予定
	hl_groups = { "IncSearch", "WarningMsg", "String", "Type" }, -- 色味
	chars = { "*", "+", "x", "o", "·" }, -- スパーク文字
	random_seed = true, -- 起動ごとに乱数シード
}

local state = {
	ns = vim.api.nvim_create_namespace("ascii_fireworks"),
	cfg = vim.deepcopy(default_config),
	timers = {}, -- 動作中アニメの管理
}

-- 小道具
local function clamp(v, a, b)
	return math.max(a, math.min(b, v))
end

local function get_window_viewport()
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	local width = vim.api.nvim_win_get_width(win)
	local height = vim.api.nvim_win_get_height(win)
	-- 画面上端/下端のバッファ行番号
	local topline = vim.fn.line("w0")
	local botline = vim.fn.line("w$")
	return {
		win = win,
		buf = buf,
		width = width,
		height = height,
		topline = topline,
		botline = botline,
	}
end

local function diagnostics_count(bufnr)
	local diags = vim.diagnostic.get(bufnr)
	return #diags
end

local function filesize_of(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return 0
	end
	local sz = vim.fn.getfsize(name)
	if sz < 0 then
		return 0
	end
	return sz
end

local function clear_extmarks(bufnr)
	pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.ns, 0, -1)
end

local function set_spark(bufnr, lnum, col, text, hl)
	-- 範囲安全化
	local lines = vim.api.nvim_buf_line_count(bufnr)
	lnum = clamp(lnum, 0, math.max(0, lines - 1))
	col = math.max(0, col)
	-- 仮想テキストで1文字を置く（折返し/幅ズレ対策で右側に置く方式）
	vim.api.nvim_buf_set_extmark(bufnr, state.ns, lnum, 0, {
		virt_text = { { text, hl } },
		virt_text_pos = "overlay",
		hl_mode = "combine",
		-- overlayはカラム補正が効きづらいので右寄せになりがち。
		-- そこで virt_text_win_col を使って絶対ウィンドウ座標に配置する。
		virt_text_win_col = col,
		priority = 4096,
	})
end

local function rand_choice(t)
	return t[math.random(#t)]
end

local function make_bursts(vp, intensity)
	-- intensity: 1(小)～3(大) 想定
	local bursts = {}
	local n = intensity -- 基本は intensity 個
	for i = 1, n do
		-- 画面内のランダム位置（ステータス/コマンドラインに被らないよう余白）
		local padx, pady = 4, 2
		local cx = math.random(padx, math.max(padx, vp.width - padx))
		local cy = math.random(vp.topline + pady - 1, math.max(vp.topline + pady - 1, vp.botline - pady - 1))
		bursts[#bursts + 1] = { cx = cx, cy = cy }
	end
	return bursts
end

local function frame_points(burst, frame, max_frames)
	-- 円周方向にだんだん広がる火花
	local points = {}
	local arms = 8
	local r = frame * 2.0 -- 半径をフレームと連動
	local aspect_ratio = 2.0 -- 縦横比補正（2.0でほぼ正円に見える）

	for k = 1, arms do
		local theta = (2 * math.pi / arms) * (k + (frame % 2) * 0.25)
		local dx = math.floor(r * math.cos(theta))
		local dy = math.floor((r * math.sin(theta)) / aspect_ratio)
		points[#points + 1] = { x = burst.cx + dx, y = burst.cy + dy }
	end
	return points
end

-- タイマーを配列から削除するヘルパー関数
local function remove_timer(timer)
	for i, t in ipairs(state.timers) do
		if t == timer then
			table.remove(state.timers, i)
			break
		end
	end
end

local function animate_once(bufnr, cfg, meta)
	-- meta: { intensity=1..3, bursts={...}, max_frames, frame_interval_ms }
	local max_frames = meta.max_frames
	local frame = 1

	local timer = vim.loop.new_timer()
	state.timers[#state.timers + 1] = timer

	timer:start(
		0,
		meta.frame_interval_ms,
		vim.schedule_wrap(function()
			if not vim.api.nvim_buf_is_loaded(bufnr) then
				timer:stop()
				timer:close()
				remove_timer(timer)
				return
			end
			clear_extmarks(bufnr)

			-- 各バーストの現フレーム描画
			for _, b in ipairs(meta.bursts) do
				local pts = frame_points(b, frame, max_frames)
				for _, p in ipairs(pts) do
					local ch = rand_choice(cfg.chars)
					local hl = rand_choice(cfg.hl_groups)
					set_spark(bufnr, p.y - 1, p.x - 1, ch, hl)
				end
				-- 中心にも少し
				if frame % 2 == 0 then
					set_spark(bufnr, b.cy - 1, b.cx - 1, rand_choice(cfg.chars), rand_choice(cfg.hl_groups))
				end
			end

			frame = frame + 1
			if frame > max_frames then
				clear_extmarks(bufnr)
				timer:stop()
				timer:close()
				remove_timer(timer)
			end
		end)
	)
end

local function fireworks_now(bufnr, opts)
	local cfg = state.cfg
	if not cfg.enable then
		return
	end
	local vp = get_window_viewport()
	if vp.buf ~= bufnr then
		return
	end

	local size = filesize_of(bufnr)
	local diag = diagnostics_count(bufnr)

	-- “実用”要素：ファイルサイズ＆診断件数に応じて派手さを調整
	local intensity = 1
	if size >= cfg.min_bytes_for_big then
		intensity = intensity + 1
	end
	if diag == 0 then
		intensity = intensity + 1
	end
	intensity = clamp(intensity, 1, 3)

	-- バースト数：上限をかけつつ intensity に連動
	local bursts = make_bursts(vp, clamp(intensity, 1, cfg.max_bursts))

	-- フレーム数は総時間 / 間隔
	local max_frames = math.max(4, math.floor(cfg.duration_ms / cfg.frame_interval_ms))

	animate_once(bufnr, cfg, {
		intensity = intensity,
		bursts = bursts,
		max_frames = max_frames,
		frame_interval_ms = cfg.frame_interval_ms,
	})
end

-- ユーザー向けAPI
function M.setup(user_config)
	state.cfg = vim.tbl_deep_extend("force", default_config, user_config or {})

	if state.cfg.random_seed then
		math.randomseed(vim.loop.hrtime() % 2 ^ 31)
	end

	-- :Fireworks コマンド（手動発火）
	vim.api.nvim_create_user_command("Fireworks", function()
		fireworks_now(vim.api.nvim_get_current_buf(), {})
	end, {})

	-- 自動コマンド
	local group = vim.api.nvim_create_augroup("AsciiFireworksAu", { clear = true })
	for _, ev in ipairs(state.cfg.events) do
		vim.api.nvim_create_autocmd(ev, {
			group = group,
			callback = function(args)
				fireworks_now(args.buf, {})
			end,
			desc = "ASCII Fireworks on save",
		})
	end
end

-- ランタイム中にオン/オフ
function M.enable()
	state.cfg.enable = true
end
function M.disable()
	state.cfg.enable = false
end
function M.toggle()
	state.cfg.enable = not state.cfg.enable
end

return M
