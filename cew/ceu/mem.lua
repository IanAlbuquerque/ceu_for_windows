MEM = {
    clss  = '',
}

function SPC ()
    return string.rep(' ',AST.iter()().__depth*2)
end

function pred_sort (v1, v2)
    return (v1.len or TP.types.word.len) > (v2.len or TP.types.word.len)
end

F = {
    Host = function (me)
        -- unescape `##´ => `#´
        local src = string.gsub(me[1], '^%s*##',  '#')
              src = string.gsub(src,   '\n%s*##', '\n#')
        CLS().native = CLS().native .. [[

#line ]]..me.ln[2]..' "'..me.ln[1]..[["
]] .. src
    end,

    Dcl_cls_pre = function (me)
        me.struct = [[
typedef struct CEU_]]..me.id..[[ {
  struct tceu_org org;
  tceu_trl trls_[ ]]..me.trails_n..[[ ];
]]
        me.native = ''
        me.funs = ''
    end,
    Dcl_cls_pos = function (me)
        if me.is_ifc then
            me.struct = 'typedef void '..TP.toc(me.tp)..';\n'
            -- interface full declarations must be delayed to after its impls.  
            local struct = [[
typedef union CEU_]]..me.id..[[_delayed {
]]
            for k, v in pairs(me.matches) do
                if v then
                    struct = struct..'\t'..TP.toc(k.tp)..' '..k.id..';\n'
                end
            end
            struct = struct .. [[
} CEU_]]..me.id..[[_delayed;
]]
            -- TODO: HACK_4: delayed declaration until use
            me.struct_delayed = struct .. '\n'
        else
            me.struct  = me.struct..'\n} '..TP.toc(me.tp)..';\n'
        end

        if me.id ~= 'Main' then
            MEM.clss = MEM.clss .. me.native .. '\n'
        end
        MEM.clss = MEM.clss .. me.struct .. '\n'

        MEM.clss = MEM.clss .. me.funs .. '\n'
--DBG('===', me.id, me.trails_n)
--DBG(me.struct)
--DBG('======================')
    end,

    Dcl_fun = function (me)
        local _, _, ins, out, id, blk = unpack(me)
        local cls = CLS()

        -- input parameters (void* _ceu_go->org, int a, int b)
        local dcl = { 'tceu_app* _ceu_app', 'tceu_org* __ceu_org' }
        for _, v in ipairs(ins) do
            local _, tp, id = unpack(v)
            dcl[#dcl+1] = TP.toc(tp)..' '..(id or '')
        end
        dcl = table.concat(dcl,  ', ')

        -- TODO: static?
        me.id = 'CEU_'..cls.id..'_'..id
        me.proto = [[
]]..TP.toc(out)..' '..me.id..' ('..dcl..[[)
]]
        if OPTS.os and ENV.exts[id] and ENV.exts[id].pre=='output' then
            -- defined elsewhere
        else
            cls.funs = cls.funs..'static '..me.proto..';\n'
        end
    end,

    Stmts_pre = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'union {\n'
    end,
    Stmts_pos = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'};\n'
    end,

    Block_pos = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'};\n'
    end,
    Block_pre = function (me)
        local cls = CLS()

        cls.struct = cls.struct..SPC()..'struct { /* BLOCK ln='..me.ln[2]..' */\n'

        if me.fins then
            for i=1, #me.fins do
            cls.struct = cls.struct .. SPC()
                            ..'u8 __fin_'..me.n..'_'..i..': 1;\n'
            end
        end

        for _, var in ipairs(me.vars) do
            local len
            --if var.isTmp or var.pre=='event' then  --
            if var.isTmp then --
                len = 0
            elseif var.pre == 'event' then --
                len = 1   --
            elseif var.pre=='pool' and (type(var.tp.arr)=='table') then
                len = 10    -- TODO: it should be big
            elseif var.cls then
                len = 10    -- TODO: it should be big
                --len = (var.tp.arr or 1) * ?
            elseif var.tp.arr then
                len = 10    -- TODO: it should be big
--[[
                local _tp = TP.deptr(var.tp)
                len = var.tp.arr * (TP.deptr(_tp) and TP.types.pointer.len
                             or (ENV.c[_tp] and ENV.c[_tp].len
                                 or TP.types.word.len)) -- defaults to word
]]
            elseif var.tp.ptr>0 or var.tp.ref then
                len = TP.types.pointer.len
            else
                len = ENV.c[var.tp.id].len
            end
            var.len = len
        end

        -- sort offsets in descending order to optimize alignment
        -- TODO: previous org metadata
        local sorted = { unpack(me.vars) }
        if me ~= CLS().blk_ifc then
            table.sort(sorted, pred_sort)   -- TCEU_X should respect lexical order
        end

        for _, var in ipairs(sorted) do
            local tp = TP.toc(var.tp)

            if var.inTop then
                var.id_ = var.id
                    -- id's inside interfaces are kept (to be used from C)
            else
                var.id_ = var.id .. '_' .. var.n
                    -- otherwise use counter to avoid clash inside struct/union
            end

            if CLS().id == var.tp.id then
                tp = 'struct '..tp  -- for types w/ pointers for themselves
            end

            if var.pre=='var' and (not var.isTmp) then
                local dcl = [[
#line ]]..var.ln[2]..' "'..var.ln[1]..[["
]]
                if var.tp.arr then
                    local tp = string.sub(tp,1,-2)  -- remove leading `*´
                    ASR(var.tp.arr.cval, me, 'invalid constant')
                    dcl = dcl .. tp..' '..var.id_..'['..var.tp.arr.cval..']'
                else
                    dcl = dcl .. tp..' '..var.id_
                end
                cls.struct = cls.struct..SPC()..'  '..dcl..';\n'
            elseif var.pre=='pool' and (type(var.tp.arr)=='table') then
                local pool_cls = ENV.clss[var.tp.id]
                if pool_cls.is_ifc then
                    -- TODO: HACK_4: delayed declaration until use
                    MEM.clss = MEM.clss .. pool_cls.struct_delayed .. '\n'
                    pool_cls.struct_delayed = ''
                    cls.struct = cls.struct .. [[
CEU_POOL_DCL(]]..var.id_..',CEU_'..var.tp.id..'_delayed,'..var.tp.arr.sval..[[)
]]
                           -- TODO: bad (explicit CEU_)
                else
                    cls.struct = cls.struct .. [[
CEU_POOL_DCL(]]..var.id_..',CEU_'..var.tp.id..','..var.tp.arr.sval..[[)
]]
                           -- TODO: bad (explicit CEU_)
                end
            end

            -- pointers ini/end to list of orgs
            if var.cls then
                cls.struct = cls.struct .. SPC() ..
                   'tceu_org_lnk __lnks_'..me.n..'_'..var.trl_orgs[1]..'[2];\n'
                    -- see val.lua for the (complex) naming
            end
        end
    end,

    ParOr_pre = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'struct {\n'
    end,
    ParOr_pos = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'};\n'
    end,
    ParAnd_pre = 'ParOr_pre',
    ParAnd_pos = 'ParOr_pos',
    ParEver_pre = 'ParOr_pre',
    ParEver_pos = 'ParOr_pos',

    ParAnd = function (me)
        local cls = CLS()
        for i=1, #me do
            cls.struct = cls.struct..SPC()..'u8 __and_'..me.n..'_'..i..': 1;\n'
        end
    end,

    AwaitT = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'s32 __wclk_'..me.n..';\n'
    end,

--[[
    AwaitS = function (me)
        for _, awt in ipairs(me) do
            if awt.__ast_isexp then
            elseif awt.tag=='Ext' then
            else
                awt.off = alloc(CLS().mem, 4)
            end
        end
    end,
]]

    Thread_pre = 'ParOr_pre',
    Thread = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'CEU_THREADS_T __thread_id_'..me.n..';\n'
        cls.struct = cls.struct..SPC()..'s8*       __thread_st_'..me.n..';\n'
    end,
    Thread_pos = 'ParOr_pos',
}

AST.visit(F)
