local _ceu2c = { ['or']='||', ['and']='&&', ['not']='!' }
local function ceu2c (op)
    return _ceu2c[op] or op
end

--[[
-- Fills nodes with "sval" and "cval".
-- sval: static value
-- cval: C value
--]]

F =
{
    Dcl_var = function (me)
        if me.var.cls then
            if me.var.tp.arr then
                ASR(me.var.tp.arr.sval, me, 'invalid static expression')
            end
        end
    end,

    Op2_call = function (me)
        local _, f, ins = unpack(me)
        if not f.cval then
            return
        end
        local ps = {}
        for i, exp in ipairs(ins) do
            if not exp.cval then
                return
            end
            ps[i] = exp.cval
        end
        me.cval = f.cval..'('..table.concat(ps,',')..')'
    end,

    Op2_any = function (me)
        local op, e1, e2 = unpack(me)
        if e1.cval and e2.cval then
            me.cval = '('..e1.cval..ceu2c(op)..e2.cval..')'
        end

        if e1.sval and e2.sval then
            local v = loadstring('return '..e1.sval..op..e2.sval)
            me.sval = v and tonumber(v())
        end
    end,
    ['Op2_-']   = 'Op2_any',
    ['Op2_+']   = 'Op2_any',
    ['Op2_%']   = 'Op2_any',
    ['Op2_*']   = 'Op2_any',
    ['Op2_/']   = 'Op2_any',
    ['Op2_|']   = 'Op2_any',
    ['Op2_&']   = 'Op2_any',
    ['Op2_<<']  = 'Op2_any',
    ['Op2_>>']  = 'Op2_any',
    ['Op2_^']   = 'Op2_any',
    ['Op2_==']  = 'Op2_any',
    ['Op2_!=']  = 'Op2_any',
    ['Op2_>=']  = 'Op2_any',
    ['Op2_<=']  = 'Op2_any',
    ['Op2_>']   = 'Op2_any',
    ['Op2_<']   = 'Op2_any',
    ['Op2_or']  = 'Op2_any',
    ['Op2_and'] = 'Op2_any',

    Op1_any = function (me)
        local op, e1 = unpack(me)
        if e1.cval then
            me.cval = '('..ceu2c(op)..e1.cval..')'
        end
        if e1.sval then
            local v = loadstring(op..e1.sval)
            me.sval = v and tonumber(v())
        end
    end,
    ['Op1_~']   = 'Op1_any',
    ['Op1_-']   = 'Op1_any',
    ['Op1_+']   = 'Op1_any',
    ['Op1_not'] = 'Op1_any',

    Op1_cast = function (me)
        local tp, exp = unpack(me)
        if exp.cval then
            me.cval = '(('..TP.toc(tp)..')'..exp.cval..')'
        end
    end,

    RawExp = function (me)
        me.cval = unpack(me)
    end,

    Nat = function (me)
        me.cval = string.sub(me[1], 2)
    end,
    STRING = function (me)
        me.cval = me[1]
    end,
    NUMBER = function (me)
        me.cval = me[1]
        me.sval = tonumber(me[1])
    end,
    NULL = function (me)
        me.cval = '((void *)0)'
        me.sval = '((void *)0)'
    end,
}

AST.visit(F)
