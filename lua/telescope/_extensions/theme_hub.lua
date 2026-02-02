local hub = require("theme-hub")
local themes = require("theme-hub.registry")
local installer = require("theme-hub.installer")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values
local entry_display = require("telescope.pickers.entry_display")

local telescope_opts
local theme_hub_picker = {
  defaults = {
    layout_strategy = "center",
    layout_config = {
      width = 0.45,
      height = 0.55,
    },
    sorting_function = function(a, b)
      if a.is_active ~= b.is_active then
        return a.is_active and not b.is_active
      end
      if a.installed ~= b.installed then
        return a.installed and not b.installed
      end
      return a.theme.name:lower() < b.theme.name:lower()
    end,
    column_widths = {
      status = 2,
      name = 20,
    },
  },
  keymaps = {
    install_theme = {
      mode = { "n", "i" },
      key = "<C-i>",
      opts = { desc = "Install theme" },
    },
    uninstall_theme = {
      mode = { "n", "i" },
      key = "<C-u>",
      opts = { desc = "Uninstall theme" },
    },
    uninstall_all = {
      mode = { "n", "i" },
      key = "<C-x>",
      opts = { desc = "Uninstall all themes" },
    },
  },
}

local function is_theme_active(theme)
  local active_theme = vim.g.colors_name
  if not active_theme then
    return false
  end

  if theme.variants then
    for _, v in ipairs(theme.variants) do
      if v.name == active_theme then
        return true, v.name
      end
    end
  end

  return theme.name == active_theme
end

function theme_hub_picker.back_to_overview(opts)
  theme_hub_picker.list_themes(opts)
end

function theme_hub_picker.list_themes(opts)
  opts = vim.tbl_deep_extend("force", theme_hub_picker.defaults, telescope_opts or {}, opts or {})

  local installed = {}
  for _, t in ipairs(hub.get_installed_themes()) do
    installed[t.name] = true
    if t.custom_name then
      installed[t.custom_name] = true
    end
  end

  local entries = {}
  for _, theme in ipairs(themes) do
    table.insert(entries, {
      theme = theme,
      installed = installed[theme.name] == true,
      is_active = is_theme_active(theme),
    })
  end

  -- Installed themes first, then alphabetical
  table.sort(entries, theme_hub_picker.defaults.sorting_function)

  local theme_display = entry_display.create({
    separator = " ",
    items = {
      { width = opts.column_widths.status },
      { width = opts.column_widths.name },
      { remaining = true },
    },
  })

  vim.api.nvim_set_hl(0, "ThemeHubActive", { fg = "#ff00ff", bold = true })

  local function normalize_mapping(name, m)
    local default = theme_hub_picker.keymaps[name]
    return {
      mode = m.mode ~= nil and m.mode or default.mode,
      key = m.key ~= nil and m.key or default.key,
      opts = m.opts ~= nil and m.opts or default.opts,
    }
  end

  opts.mappings = opts.mappings or opts.keymaps

  local merged = vim.tbl_deep_extend("force", theme_hub_picker.keymaps, opts.mappings or {})

  local mappings = {}
  for name, m in pairs(merged) do
    mappings[name] = normalize_mapping(name, m)
  end

  pickers
    .new(opts, {
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          local theme = entry.theme
          local status = entry.installed and "✔" or " "
          local name = theme.name
          local desc = theme.description or ""

          return {
            value = entry,
            ordinal = name .. " " .. desc,
            display = function()
              return theme_display({
                {
                  status,
                  entry.installed and "ThemeHubActive" or nil,
                },
                {
                  name,
                  entry.is_active and "ThemeHubActive" or nil,
                },
                {
                  desc,
                  entry.is_active and "ThemeHubActive" or nil,
                },
              })
            end,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        local function select_theme()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end

          local entry = selection.value
          local theme = entry.theme

          actions.close(prompt_bufnr)

          -- not installed
          if not entry.installed then
            if hub.config.auto_install_on_select then
              installer.install(theme)
            else
              theme_hub_picker.list_theme_actions(theme, opts)
            end
            return
          end

          -- installed
          if theme.variants and #theme.variants > 0 then
            theme_hub_picker.list_variants(theme, opts)
          else
            theme_hub_picker.list_theme_actions(theme, opts)
          end
        end

        local function install()
          local sel = action_state.get_selected_entry()
          if sel then
            installer.install(sel.value.theme)
          end
        end

        local function uninstall()
          local sel = action_state.get_selected_entry()
          if not sel then
            return
          end

          hub.uninstall(sel.value.theme.name)
          actions.close(prompt_bufnr)
          theme_hub_picker.back_to_overview(opts)
        end

        local function uninstall_all()
          hub.uninstall_all()
          actions.close(prompt_bufnr)
          theme_hub_picker.back_to_overview(opts)
        end

        for _, mode in ipairs(mappings.install_theme.mode) do
          map(mode, mappings.install_theme.key, install, mappings.install_theme.opts)
        end

        for _, mode in ipairs(mappings.uninstall_theme.mode) do
          map(mode, mappings.uninstall_theme.key, uninstall, mappings.uninstall_theme.opts)
        end

        for _, mode in ipairs(mappings.uninstall_all.mode) do
          map(mode, mappings.uninstall_all.key, uninstall_all, mappings.uninstall_all.opts)
        end

        map({ "n", "i" }, "<cr>", select_theme, { desc = "Select Theme" })

        map("n", "q", function()
          actions.close(prompt_bufnr)
          theme_hub_picker.back_to_overview(opts)
        end, { desc = "Back to overview" })

        return true
      end,
    })
    :find()
end

-- For themes without variants
function theme_hub_picker.list_theme_actions(theme, opts)
  opts = vim.tbl_deep_extend("force", theme_hub_picker.defaults, opts or {})

  local entries = {}

  local is_installed = false
  for _, t in ipairs(hub.get_installed_themes()) do
    if t.name == theme.name then
      is_installed = true
      break
    end
  end

  if not is_installed then
    table.insert(entries, {
      kind = "install",
      display = "Install",
    })
  else
    table.insert(entries, {
      kind = "apply",
      display = "Apply",
    })

    table.insert(entries, {
      kind = "uninstall",
      display = "Uninstall",
    })
  end

  table.insert(entries, {
    kind = "back",
    display = "Back to overview",
  })

  local action_display = entry_display.create({
    items = {
      { remaining = true },
    },
  })

  pickers
    .new(opts, {
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            ordinal = entry.display,
            display = function()
              return action_display({ entry.display })
            end,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        local function select_action()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end

          actions.close(prompt_bufnr)

          local v = selection.value

          if v.kind == "install" then
            installer.install(theme)
          elseif v.kind == "apply" then
            installer.apply(theme.custom_name or theme.name)
          elseif v.kind == "uninstall" then
            installer.uninstall(theme.name)
            theme_hub_picker.back_to_overview(opts)
          elseif v.kind == "back" then
            theme_hub_picker.back_to_overview(opts)
          end
        end

        map({ "n", "i" }, "<cr>", select_action, { desc = "Select action" })

        map("n", "q", function()
          actions.close(prompt_bufnr)
          theme_hub_picker.back_to_overview(opts)
        end)

        return true
      end,
    })
    :find()
end

function theme_hub_picker.list_variants(theme, opts)
  opts = vim.tbl_deep_extend("force", theme_hub_picker.defaults, opts or {})

  local entries = {}
  for _, variant in ipairs(theme.variants) do
    table.insert(entries, {
      kind = "variant",
      name = variant.name,
      display = "Apply: " .. (variant.display or variant.name),
    })
  end

  table.insert(entries, { kind = "uninstall", display = "Uninstall" })
  table.insert(entries, { kind = "back", display = "Back to overview" })

  local variant_display = entry_display.create({
    items = {
      { remaining = true },
    },
  })

  pickers
    .new(opts, {
      finder = finders.new_table({
        results = entries,
        entry_maker = function(variant)
          local name = variant.display or variant.name
          return {
            value = variant,
            ordinal = variant.display,
            display = function()
              return variant_display({
                name,
              })
            end,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        local function select_variant()
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end

          actions.close(prompt_bufnr)

          local v = selection.value

          if v.kind == "variant" then
            installer.apply(v.name)
          elseif v.kind == "uninstall" then
            installer.uninstall(theme.name)
          elseif v.kind == "back" then
            theme_hub_picker.back_to_overview(opts)
          end
        end

        map({ "n", "i" }, "<cr>", select_variant, { desc = "Select variant" })

        map("i", "<esc>", function()
          actions.close(prompt_bufnr)
          theme_hub_picker.back_to_overview(opts)
        end, { desc = "Back to overview" })

        map("n", "q", function()
          actions.close(prompt_bufnr)
          theme_hub_picker.back_to_overview(opts)
        end)

        return true
      end,
    })
    :find()
end

return require("telescope").register_extension({
  setup = function(topts)
    telescope_opts = topts
  end,
  exports = theme_hub_picker.list_themes,
})
