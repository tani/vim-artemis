local api = vim.api

describe('options', function()
  it('vim.o booleans / numbers / strings', function()
    vim.o.number = true
    eq(vim.o.number, true)
    vim.o.number = false
    eq(vim.o.number, false)
    vim.o.tabstop = 4
    eq(vim.o.tabstop, 4)
    vim.o.matchpairs = '(:),{:}'
    eq(vim.o.matchpairs, '(:),{:}')
  end)
  it('short names', function()
    vim.o.ts = 3
    eq(vim.o.tabstop, 3)
  end)
  it('vim.bo / vim.wo', function()
    vim.cmd('enew!')
    vim.bo.shiftwidth = 5
    eq(vim.bo.shiftwidth, 5)
    vim.wo.wrap = false
    eq(vim.wo.wrap, false)
    vim.wo.wrap = true
  end)
  it('vim.opt list / append / remove', function()
    vim.opt.matchpairs = { '(:)', '[:]' }
    eq(vim.o.matchpairs, '(:),[:]')
    vim.opt.matchpairs:append('{:}')
    eq(vim.o.matchpairs, '(:),[:],{:}')
    vim.opt.matchpairs:remove('[:]')
    eq(vim.o.matchpairs, '(:),{:}')
    eq(vim.opt.matchpairs:get(), { '(:)', '{:}' })
  end)
  it('vim.opt map', function()
    vim.opt.listchars = { tab = '> ', trail = '-' }
    eq(vim.opt.listchars:get(), { tab = '> ', trail = '-' })
  end)
  it('get_option_value / set_option_value', function()
    api.nvim_set_option_value('tabstop', 7, {})
    eq(api.nvim_get_option_value('tabstop', {}), 7)
    eq(api.nvim_get_option_value('tabstop', { scope = 'global' }), 7)
    local ok = pcall(api.nvim_get_option_value, 'nosuchoption', {})
    eq(ok, false)
  end)
end)

describe('variables', function()
  it('vim.g with tables', function()
    vim.g.artemis_t = { a = 1, b = { 1, 2 } }
    eq(vim.g.artemis_t, { a = 1, b = { 1, 2 } })
    vim.g.artemis_t = nil
    eq(vim.g.artemis_t, nil)
  end)
  it('vim.g scalar / vimscript sees it', function()
    vim.g.artemis_n = 42
    eq(vim.fn.eval('g:artemis_n'), 42)
    eq(api.nvim_get_var('artemis_n'), 42)
  end)
  it('vim.b / vim.w', function()
    vim.cmd('enew!')
    vim.b.artemis_b = 'x'
    eq(vim.b.artemis_b, 'x')
    eq(vim.b[0].artemis_b, 'x')
    vim.b.artemis_b = nil
    eq(vim.b.artemis_b, nil)
  end)
  it('vim.v', function()
    eq(type(vim.v.version), 'number')
  end)
  it('vim.env', function()
    vim.env.ARTEMIS_TEST_ENV = 'hi'
    eq(vim.env.ARTEMIS_TEST_ENV, 'hi')
    vim.env.ARTEMIS_TEST_ENV = nil
    eq(vim.env.ARTEMIS_TEST_ENV, nil)
  end)
end)

describe('vim.fn', function()
  it('converts args and results', function()
    eq(vim.fn.len({ 1, 2, 3 }), 3)
    eq(vim.fn.split('a b', ' '), { 'a', 'b' })
    eq(vim.fn.extend({ a = 1 }, { b = 2 }), { a = 1, b = 2 })
    eq(vim.fn.toupper('abc'), 'ABC')
  end)
  it('errors raise', function()
    eq(pcall(vim.fn.nonexistent_function_xyz), false)
  end)
  it('callbacks as funcref', function()
    local r = vim.fn.map({ 1, 2, 3 }, function(_, v) return v * 2 end)
    eq(r, { 2, 4, 6 })
  end)
end)
