local vimx = require('artemis')

describe('artemis v1 API', function()
  it('nested variable assignment writes through', function()
    vimx.g.artemis_v1 = { colorscheme = 'a', inner = { x = 1 } }
    vimx.g.artemis_v1.colorscheme = 'b'
    vimx.g.artemis_v1.inner.x = 2
    eq(vim.g.artemis_v1, { colorscheme = 'b', inner = { x = 2 } })
    vimx.g.artemis_v1 = nil
  end)
  it('fn chaining with dots', function()
    vim.cmd('function! ArtemisV1Add(a, b) abort\n return a:a + a:b\n endfunction')
    eq(vimx.fn.ArtemisV1Add(1, 2), 3)
    -- dots become '#': the (missing) autoload function is named in the error
    local ok, err = pcall(function() return vimx.fn.ArtemisV1.add(1, 2) end)
    eq(ok, false)
    eq(tostring(err):find('ArtemisV1#add', 1, true) ~= nil, true)
  end)
  it('cmd / eval', function()
    vimx.cmd.let('g:artemis_v1b = 7')
    eq(vimx.eval('g:artemis_v1b'), 7)
  end)
  it('create_command / delete_command', function()
    local hit
    vimx.create_command('ArtemisV1Cmd', function(o) hit = o.args end, { nargs = '*' })
    vim.cmd('ArtemisV1Cmd hi')
    eq(hit, 'hi')
    vimx.delete_command('ArtemisV1Cmd')
  end)
  it('create_buf_command', function()
    vim.cmd('enew!')
    local hit = 0
    vimx.create_buf_command(0, 'ArtemisV1Buf', function() hit = hit + 1 end, {})
    vim.cmd('ArtemisV1Buf')
    eq(hit, 1)
  end)
  it('opt', function()
    vimx.opt.matchpairs = { '(:)', '{:}' }
    vimx.opt.matchpairs:append('[:]')
    eq(vimx.o.matchpairs, '(:),{:},[:]')
  end)
end)
