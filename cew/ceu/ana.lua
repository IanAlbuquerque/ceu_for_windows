-- TODO: rename to flow
ANA = {
    ana = {
        isForever  = nil,
        reachs   = 0,      -- unexpected reaches
        unreachs = 0,      -- unexpected unreaches
    },
}

-- avoids counting twice (due to loops)
-- TODO: remove
local __inc = {}
function INC (me, c)
    if __inc[me] then
        return true
    else
        ANA.ana[c] = ANA.ana[c] + 1
        __inc[me] = true
        return false
    end
end

-- [false]  => never terminates
-- [true]   => terminates w/o event

function OR (me, sub, short)

    -- TODO: short
    -- short: for ParOr/Loop/SetBlock if any sub.pos is equal to me.pre,
    -- then we have a "short circuit"

    for k in pairs(sub.ana.pos) do
        if k ~= false then
            me.ana.pos[false] = nil      -- remove NEVER
            me.ana.pos[k] = true
        end
    end
end

function COPY (n)
    local ret = {}
    for k in pairs(n) do
        ret[k] = true
    end
    return ret
end

function ANA.CMP (n1, n2)
    return ANA.HAS(n1, n2) and ANA.HAS(n2, n1)
end

function ANA.HAS (n1, n2)
    for k2 in pairs(n2) do
        if not n1[k2] then
            return false
        end
    end
    return true
end

local LST = {
    Do=true, Stmts=true, Block=true, Root=true, Dcl_cls=true,
    Pause=true,
}

F = {
    Root_pos = function (me)
        ANA.ana.isForever = not (not me.ana.pos[false])
    end,

    Node_pre = function (me)
        if me.ana then
            return
        end

        local top = AST.iter()()
        me.ana = {
            pre  = (top and COPY(top.ana.pre)) or { [true]=true },
        }
    end,
    Node = function (me)
        if me.ana.pos then
            return
        end
        if LST[me.tag] and me[#me] then
            me.ana.pos = COPY(me[#me].ana.pos)  -- copy lst child pos
        else
            me.ana.pos = COPY(me.ana.pre)       -- or copy own pre
        end
    end,

    Dcl_cls_pre = function (me)
        if me ~= MAIN then
            me.ana.pre = { [me.id]=true }
        end
    end,
    Orgs = function (me)
        me.ana.pos = { [false]=true }       -- orgs run forever
    end,

    Stmts_bef = function (me, sub, i)
        if i == 1 then
            -- first sub copies parent
            sub.ana = {
                pre = COPY(me.ana.pre)
            }
        else
            -- broken sequences
            if sub.tag~='Host' and me[i-1].ana.pos[false] and (not me[i-1].ana.pre[false]) then
                --ANA.ana.unreachs = ANA.ana.unreachs + 1
                me.__unreach = true
                WRN( INC(me, 'unreachs'),
                     sub, 'statement is not reachable')
            end
            -- other subs follow previous
            sub.ana = {
                pre = COPY(me[i-1].ana.pos)
            }
        end
    end,

    ParOr_pos = function (me)
        me.ana.pos = { [false]=true }
        for _, sub in ipairs(me) do
            OR(me, sub, true)
        end
        if me.ana.pos[false] then
            --ANA.ana.unreachs = ANA.ana.unreachs + 1
            WRN( INC(me, 'unreachs'),
                 me, 'at least one trail should terminate')
        end
    end,

    ParAnd_pos = function (me)
        -- if any of the sides run forever, then me does too
        -- otherwise, behave like ParOr
        for _, sub in ipairs(me) do
            if sub.ana.pos[false] then
                me.ana.pos = { [false]=true }
                --ANA.ana.unreachs = ANA.ana.unreachs + 1
                WRN( INC(me, 'unreachs'),
                     sub, 'trail should terminate')
                return
            end
        end

        -- like ParOr, but remove [true]
        local onlyTrue = true
        me.ana.pos = { [false]=true }
        for _, sub in ipairs(me) do
            OR(me, sub)
            if not sub.ana.pos[true] then
                onlyTrue = false
            end
        end
        if not onlyTrue then
            me.ana.pos[true] = nil
        end
    end,

    ParEver_pos = function (me)
        me.ana.pos = { [false]=true }
        local ok = false
        for _, sub in ipairs(me) do
            if sub.ana.pos[false] then
                ok = true
                break
            end
        end
        if not ok then
            --ANA.ana.reachs = ANA.ana.reachs + 1
            WRN( INC(me, 'reachs'),
                 me, 'all trails terminate')
        end
    end,

    If = function (me)
        me.ana.pos = { [false]=true }
        for _, sub in ipairs{me[2],me[3]} do
            OR(me, sub)
        end
    end,

    SetBlock_pre = function (me)
        me.ana.pos = { [false]=true }   -- `return/break´ may change this
    end,
    Escape = function (me)
        local top = AST.iter((me.tag=='Escape' and 'SetBlock') or 'Loop')()
        me.ana.pos = COPY(me.ana.pre)
        OR(top, me, true)
        me.ana.pos = { [false]='esc' }   -- diff from [false]=true
    end,
    SetBlock = function (me)
        local blk = me[1]
        if not blk.ana.pos[false] then
            --ANA.ana.reachs = ANA.ana.reachs + 1
            WRN( INC(me, 'reachs'),
                 blk, 'missing `escape´ statement for the block')
        end
    end,

    Loop_pre = 'SetBlock_pre',
    Break    = 'Escape',

    Loop = function (me)
        if me.bound then
            me.ana.pos = COPY(me[1].ana.pos)
            return      -- guaranteed to terminate
        end

        if me[1].ana.pos[false] then
            --ANA.ana.unreachs = ANA.ana.unreachs + 1
            WRN( INC(me, 'unreachs'),
                 me, '`loop´ iteration is not reachable')
        end
    end,

    Thread = 'Async',
    Async = function (me)
        if me.ana.pre[false] then
            me.ana.pos = COPY(me.ana.pre)
        else
            me.ana.pos = { ['ASYNC_'..me.n]=true }  -- assume it terminates
        end
    end,

--[[
-- TODO: remove
-- not needed after SetAwait => AwaitX;SetExp
    SetAwait = function (me)
        local _, awt, set = unpack(me)
        set.ana.pre = COPY(awt.ana.pos)
        set.ana.pos = COPY(awt.ana.pos)
        me.ana.pre = COPY(awt.ana.pre)
        me.ana.pos = COPY(set.ana.pos)
    end,
]]

    AwaitS = function (me)
        DBG'TODO - ana.lua - AwaitS'
    end,

    AwaitExt_aft = function (me, sub, i)
        if i > 1 then
            return
        end

        -- between Await and Until

        local awt, cnd = unpack(me)

        local t
        if me.ana.pre[false] then
            t = { [false]=true }
        else
            -- enclose with a table to differentiate each instance
            if me.tag == 'AwaitExt' then
                t = { [{awt.evt}]=true }
            elseif me.tag == 'AwaitInt' then
                -- use "var" as identifier (why "evt" doesn't work?)
                t = { [{awt.var}]=true }
            else    -- 'AwaitT'
                t = { [{awt.evt or 'WCLOCK'}]=true }
            end
        end
        me.ana.pos = COPY(t)
        if cnd then
            cnd.ana = {
                pre = COPY(t),
            }
        end
    end,
    AwaitInt_aft = 'AwaitExt_aft',
    AwaitT_aft   = 'AwaitExt_aft',

    AwaitN = function (me)
        me.ana.pos = { [false]=true }
    end,
}

local _union = function (a, b, keep)
    if not keep then
        local old = a
        a = {}
        for k in pairs(old) do
            a[k] = true
        end
    end
    for k in pairs(b) do
        a[k] = true
    end
    return a
end

-- TODO: remove
-- if nested node is reachable from "pre", join with loop POS
function ANA.union (root, pre, POS)
    local t = {
        Node = function (me)
            if me.ana.pre[pre] then         -- if matches loop begin
                _union(me.ana.pre, POS, true)
            end
        end,
    }
    AST.visit(t, root)
end

AST.visit(F)
