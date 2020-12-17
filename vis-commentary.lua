--
-- vis-commentary
--
-- comment strings and matching patterns are taken from:
-- https://github.com/rgieseke/textadept/blob/9906c1fcec1c33c6a83c33dc7874669b5c6113f8/modules/textadept/editing.lua
--

local comment_string = {
    actionscript='//', ada='--', ansi_c='/*|*/', antlr='//', apdl='!', apl='#',
    applescript='--', asp='\'', autoit=';', awk='#', b_lang='//', bash='#',
    batch=':', bibtex='%', boo='#', chuck='//', cmake='#', coffeescript='#',
    context='%', cpp='//', crystal='#', csharp='//', css='/*|*/', cuda='//',
    desktop='#', django='{#|#}', dmd='//', dockerfile='#', dot='//',
    eiffel='--', elixir='#', erlang='%', faust='//', fish='#', forth='|\\',
    fortran='!', fsharp='//', gap='#', gettext='#', gherkin='#', glsl='//',
    gnuplot='#', go='//', groovy='//', gtkrc='#', haskell='--', html='<!--|-->',
    icon='#', idl='//', inform='!', ini='#', Io='#', java='//', javascript='//',
    json='/*|*/', jsp='//', latex='%', ledger='#', less='//', lilypond='%',
    lisp=';', logtalk='%', lua='--', makefile='#', markdown='<!--|-->', matlab='#', 
    moonscript='--', myrddin='//', nemerle='//', nsis='#', objective_c='//', 
    pascal='//', perl='#', php='//', pico8='//', pike='//', pkgbuild='#', prolog='%',
    props='#', protobuf='//', ps='%', pure='//', python='#', rails='#', rc='#',
    rebol=';', rest='.. ', rexx='--', rhtml='<!--|-->', rstats='#', ruby='#',
    rust='//', sass='//', scala='//', scheme=';', smalltalk='"|"', sml='(*)',
    snobol4='#', sql='#', tcl='#', tex='%', text='', toml='#', vala='//',
    vb='\'', vbscript='\'', verilog='//', vhdl='--', wsf='<!--|-->',
    xml='<!--|-->', yaml='#'
}

-- how many bytes are in the last character of a range
local function bytes_in_last_char(range)
    local text = vis.win.file:content(range) .. 'a'
    local before_lchar = utf8.offset(text, -2)
    local after_lchar  = utf8.offset(text, -1)

    return after_lchar - before_lchar
end

-- escape all magic characters with a '%'
local function esc(str)
    if not str then return "" end
    return (str:gsub('%%', '%%%%')
        :gsub('^%^', '%%^')
        :gsub('%$$', '%%$')
        :gsub('%(', '%%(')
        :gsub('%)', '%%)')
        :gsub('%.', '%%.')
        :gsub('%[', '%%[')
        :gsub('%]', '%%]')
        :gsub('%*', '%%*')
        :gsub('%+', '%%+')
        :gsub('%-', '%%-')
        :gsub('%?', '%%?'))
end

local function comment_line(lines, lnum, prefix, suffix, sel)
    local file = vis.win.file
    local _, sot_col = lines[lnum]:find('^%s*%S')

    sel:to(lnum, sot_col)
    local sot_pos = sel.pos

    -- we can't replace text in the line with gsub, we'd risk erasing the mark
    -- needed to restore initial selection
    file:insert(sot_pos, prefix .. ' ')

    if suffix ~= '' then
        local eot_col = lines[lnum]:find('%s*$')

        sel:to(lnum, eot_col)
        local eot_pos = sel.pos

        file:insert(eot_pos, ' ' .. suffix)
    end
end

local function uncomment_line(lines, lnum, prefix, suffix, sel)
    local file = vis.win.file
    local _, sot_col = lines[lnum]:find('^%s*%S')
    local pref_len, suff_len = prefix:len(), suffix:len()

    sel:to(lnum, sot_col)
    local sopref_pos = sel.pos
    local symbl_after_pref = file:content(sopref_pos + pref_len, 1)

    if symbl_after_pref == ' ' then
        pref_len = pref_len + 1 -- + space
    end

    file:delete(sopref_pos, pref_len)

    if suffix ~= '' then
        local sosuff_byte = lines[lnum]:find(' ?' .. esc(suffix) .. '%s*$') -- start of suffix byte pos

        sel:to(lnum, 1)
        local sosuff_pos = sel.pos + sosuff_byte - 1 -- workaround for multi-byte chars
        local symbl_before_suff = file:content(sosuff_pos, 1)

        if symbl_before_suff == ' ' then
            suff_len = suff_len + 1 -- + space
        end

        file:delete(sosuff_pos, suff_len)
    end
end

local function is_comment(line, prefix)
    return (line:match("^%s*(.+)"):sub(0, #prefix) == prefix)
end

local function toggle_line_comment(lines, lnum, prefix, suffix, sel)
    if not lines or not lines[lnum] then return end
    if not lines[lnum]:match("^%s*(.+)") then return end -- ignore empty lines
    if is_comment(lines[lnum], prefix) then
        uncomment_line(lines, lnum, prefix, suffix, sel)
    else
        comment_line(lines, lnum, prefix, suffix, sel)
    end
end

-- if one line inside the block is not a comment, comment the block.
-- only uncomment, if every single line is comment.
local function block_comment(lines, a, b, prefix, suffix, sel)
    local uncomment = true
    for i=a,b do
        if lines[i]:match("^%s*(.+)") and not is_comment(lines[i], prefix) then
            uncomment = false
        end
    end

    if uncomment then
        for i=a,b do
            if lines[i]:match("^%s*(.+)") then
                uncomment_line(lines, i, prefix, suffix, sel)
            end
        end
    else
        for i=a,b do
            if lines[i]:match("^%s*(.+)") then
                comment_line(lines, i, prefix, suffix, sel)
            end
        end
    end
end

vis:map(vis.modes.NORMAL, "gcc", function()
    local win = vis.win
    local file = win.file
    local lines = file.lines
    local comment = comment_string[win.syntax]
    if not comment then return end
    local prefix, suffix = comment:match('^([^|]+)|?([^|]*)$')
    if not prefix then return end

    for sel in win:selections_iterator() do
        local lnum = sel.line
        local m = file:mark_set(sel.pos)

        toggle_line_comment(lines, lnum, prefix, suffix, sel)

        local pos = file:mark_get(m)
        if pos then -- if the cursor was not on the prefix/suffix when uncommenting
            sel.pos = pos  -- restore cursor position
        else
            sel:to(lnum, 1)
        end
    end

    win:draw()
end, "Toggle comment on a the current line")

local function visual_f(i)
    return function()
        local win = vis.win
        local file = win.file
        local lines = file.lines
        local sel_flip = false

        local comment = comment_string[win.syntax]
        if not comment then return end

        local prefix, suffix = comment:match('^([^|]+)|?([^|]*)$')
        if not prefix then return end

        for sel in win:selections_iterator() do
            local r = sel.range
            local lnum = sel.line     -- line number of cursor

            if sel.anchored and r then
                local cursor_was = 'start'
                local lchar_bytes = bytes_in_last_char(r)
                if sel.pos + lchar_bytes == r.finish then
                    cursor_was = 'finish'
                end

                sel.pos = r.start
                local a = sel.line
                local start_m = file:mark_set(sel.pos)
                sel.pos = r.finish
                local b = sel.line - i
                local finish_m = file:mark_set(sel.pos - lchar_bytes)

                block_comment(lines, a, b, prefix, suffix, sel)

                r.start = file:mark_get(start_m)
                r.finish = file:mark_get(finish_m)

                -- if the cursor was not on the prefix/suffix when uncommenting
                if r.start and r.finish then
                    r.finish = r.finish + lchar_bytes

                    sel.range = r -- restore selection

                    local pos = sel.pos
                    if cursor_was == 'finish' then
                        pos = sel.pos + lchar_bytes
                    end
                    -- if the cursor is not at the side it was, restore its position
                    if pos ~= sel.range[cursor_was] then
                        sel_flip = true
                    end
                else
                    sel:to(lnum, 1)

                    if #win.selections == 1 then
                        vis.mode = vis.modes.NORMAL -- go to normal mode
                    end
                end
            end
        end

        if sel_flip then
            vis:feedkeys('<vis-selection-flip>')
        end

        win:draw()
    end
end

vis:map(vis.modes.VISUAL_LINE, "gc", visual_f(1), "Toggle comment on the selected lines")
vis:map(vis.modes.VISUAL, "gc", visual_f(0), "Toggle comment on the selected lines")

