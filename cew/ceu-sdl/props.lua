PROPS = {
    has_exts    = false,
    has_wclocks = false,
    has_ints    = false,
    has_asyncs  = false,
    has_threads = false,
    has_orgs    = false,
    has_news    = false,
    has_news_pool   = false,
    has_news_malloc = false,
    has_ifcs    = false,
    has_clear   = false,
    has_pses    = false,
    has_ret     = false,
    has_lua     = false,
    has_orgs_watching = false,
}

local NO_atomic = {
    Finalize=true, Finally=true,
    Host=true, Thread=true,
    ParEver=true, ParOr=true, ParAnd=true,
    AwaitS=true, AwaitExt=true, AwaitInt=true, AwaitN=true, AwaitT=true,
    EmitInt=true, EmitExt=true,
    Pause=true,
    -- TODO:
    Loop=true, Break=true, Escape=true,
    Op2_call=true,
}

local NO_fun = {
    Finalize=true, Finally=true,
    Host=true, Thread=true,
    ParEver=true, ParOr=true, ParAnd=true,
    AwaitS=true, AwaitExt=true, AwaitInt=true, AwaitN=true, AwaitT=true,
    EmitInt=true, --EmitExt=true,
    Pause=true,
}

local NO_fin = {
    Finalize=true, Finally=true,
    Host=true, Escape=true, Async=true, Thread=true,
    ParEver=true, ParOr=true, ParAnd=true,
    AwaitS=true, AwaitExt=true, AwaitInt=true, AwaitN=true, AwaitT=true,
    EmitInt=true,
    Pause=true,
}

local NO_async = {
    Async=true, Thread=true,
    ParEver=true, ParOr=true, ParAnd=true,
    AwaitS=true, AwaitExt=true, AwaitInt=true, AwaitN=true, AwaitT=true,
    EmitInt=true,
    Pause=true,
    Escape=true,
    Finalize=true,
}

local NO_thread = {
    Async=true, Thread=true,
    ParEver=true, ParOr=true, ParAnd=true,
    AwaitS=true, AwaitExt=true, AwaitInt=true, AwaitN=true, AwaitT=true,
    EmitInt=true, EmitExt=true, EmitT=true,
    Pause=true,
    Escape=true,
    Finalize=true,
}

local NO_constr = {
    --Finalize=true, Finally=true,
    Escape=true, Async=true, Thread=true,
    ParEver=true, ParOr=true, ParAnd=true,
    AwaitS=true, AwaitExt=true, AwaitInt=true, AwaitN=true, AwaitT=true,
    EmitInt=true,
    Pause=true,
}

-- Loop, SetBlock may need clear
-- if break/return are in parallel w/ something
--                  or inside block that needs_clr
function NEEDS_CLR (top)
    for n in AST.iter() do
        if n.tag == top.tag then
            break
        elseif n.tag == 'ParEver' or
               n.tag == 'ParAnd'  or
               n.tag == 'ParOr'   or
               n.tag == 'Block' and n.needs_clr then
            PROPS.has_clear = true
            top.needs_clr = true
            break
        end
    end
end

function HAS_FINS ()
    for n in AST.iter() do
        if n.tag == 'Block'    or
           n.tag == 'ParOr'    or
           n.tag == 'Loop'     or
           n.tag == 'SetBlock' then
            n.needs_clr_fin = true
        end
    end
end

F = {
    Node_pre = function (me)
        if NO_atomic[me.tag] then
            ASR(not AST.par(me,'Atomic'), me,
                'not permitted inside `atomic´')
        end
        if NO_fun[me.tag] then
            ASR(not AST.par(me,'Dcl_fun'), me,
                'not permitted inside `function´')
        end
        if NO_fin[me.tag] then
            ASR(not AST.par(me,'Finally'), me,
                'not permitted inside `finalize´')
        end
        if NO_async[me.tag] then
            ASR(not AST.par(me,'Async'), me,
                    'not permitted inside `async´')
        end
        if NO_thread[me.tag] then
            ASR(not AST.par(me,'Thread'), me,
                    'not permitted inside `thread´')
        end
        if NO_constr[me.tag] then
            ASR(not AST.par(me,'Dcl_constr'), me,
                    'not permitted inside a constructor')
        end
    end,

    Block_pre = function (me)       -- _pre: break/return depends on it
        if me.fins then
            me.needs_clr = true
            me.needs_clr_fin = true
            PROPS.has_clear = true
        end

        for _, var in ipairs(me.vars) do
            if var.cls then
                me.needs_clr = true
                PROPS.has_clear = true
            end
            if var.pre=='pool' then
                PROPS.has_news = true
                if var.tp.arr==true then
                    PROPS.has_news_malloc = true       -- pool T[]  ts
                else
                    PROPS.has_news_pool = true         -- pool T[N] ts
                end
            end
        end

        if me.needs_clr then
            HAS_FINS()  -- TODO (-ROM): could avoid ors w/o fins
        end
    end,
    Free = function (me)
        PROPS.has_news = true
        PROPS.has_clear = true
    end,
    Spawn = function (me)
        local _,pool,_ = unpack(me)

        --PROPS.has_news = true    (pool does this)
        if pool and pool.lst.var.tp.arr==true then
            PROPS.has_news_malloc = true       -- pool T[]  ts
        else
            PROPS.has_news_pool = true         -- pool T[N] ts
        end

        --PROPS.has_clear = true   (var.cls does this)
        --me.blk.needs_clr = true   (var.cls does this)
        ASR(not AST.iter'BlockI'(), me,
                'not permitted inside an interface')
    end,

    ParOr = function (me)
        me.needs_clr = true
        PROPS.has_clear = true

        -- detects if "isWatching" an org
        if me.isWatching then
            local tp = me.isWatching.tp
            if (tp and tp.ptr==1 and ENV.clss[tp.id]) then
                PROPS.has_orgs_watching = true
            end
        end
    end,

    Loop_pre = function (me)
        me.brks = {}
    end,
    Break = function (me)
        local loop = AST.iter'Loop'()
        ASR(loop, me, 'break without loop')
        loop.brks[me] = true
        loop.has_break = true

        NEEDS_CLR(loop)

        local fin = AST.iter'Finally'()
        ASR(not fin or fin.__depth<loop.__depth, me,
                'not permitted inside `finalize´')
        -- TODO: same for return

        local async = AST.iter(AST.pred_async)()
        if async then
            local loop = AST.iter'Loop'()
            ASR(loop.__depth>async.__depth, me, '`break´ without loop')
        end
    end,

    SetBlock_pre = function (me)
        me.rets = {}
        ASR(not AST.iter'BlockI'(), me,
                'not permitted inside an interface')
    end,
    Escape = function (me)
        local blk = AST.iter'SetBlock'()
        blk.rets[me] = true
        blk.has_escape = true

        NEEDS_CLR(blk)
    end,

    Return = function (me)
        ASR(AST.iter'Dcl_fun'(), me,
                'not permitted outside a function')
    end,

    Outer = function (me)
        ASR(AST.par(me,'Dcl_constr'), me,
            '`outer´ can only be unsed inside constructors')
    end,

    Dcl_cls = function (me)
        if me.id ~= 'Main' then
            PROPS.has_orgs = true
            PROPS.has_ints = true      -- all have "emit _ok"
        end
        if me.is_ifc then
            PROPS.has_ifcs = true
        end
    end,

    Dcl_ext = function (me)
        PROPS.has_exts = true
    end,

    Dcl_var = function (me)
        if me.var.cls then
            -- <class T with var U u; end>
            ASR(not AST.iter'BlockI'(), me,
                    'not permitted inside an interface')
        end
    end,

    Async = function (me)
        PROPS.has_asyncs = true
    end,
    Thread = function (me)
        PROPS.has_threads = true
    end,
    Sync = function (me)
        ASR(AST.iter'Thread'(), me,'not permitted outside `thread´')
    end,

    Pause = function (me)
        PROPS.has_pses = true
    end,

    _loop1 = function (me)
        for loop in AST.iter'Loop' do
            if loop.isEvery then
                ASR(me.isEvery, me,
                    '`every´ cannot contain `await´')
            end
        end
    end,

    AwaitT = function (me)
        PROPS.has_wclocks = true
        F._loop1(me)
    end,
    AwaitInt = function (me)
        PROPS.has_ints = true
        F._loop1(me)
    end,
    AwaitExt = function (me)
        F._loop1(me)
    end,
    AwaitN = function (me)
        F._loop1(me)
    end,
    AwaitS = function (me)
        for _, awt in ipairs(me) do
            if awt.__ast_isexp then
                F.AwaitInt(me)
            elseif awt.tag=='Ext' then
                F.AwaitExt(me)
            else
                F.AwaitT(me)
            end
        end
    end,

    EmitInt = function (me)
        PROPS.has_ints = true
    end,

    EmitExt = function (me)
        local op, ext = unpack(me)
        if ext.evt.pre == 'input' then
            ASR( AST.par(me,'Async') or op=='call',
                me, 'invalid `'..op..'´')
                    -- no <emit I> on sync
        end

        if AST.par(me,'Dcl_fun') then
            ASR(op=='call', me, 'invalid `emit´')
        end
    end,
    EmitT = function (me)
        ASR(AST.par(me,'Async'),
            me,'not permitted outside `async´')
    end,

    SetExp = function (me)
        local _, fr, to = unpack(me)
        local thr = AST.par(me, 'Thread')
        if thr and (not to) then
            ASR( thr.__depth <= AST.iter'SetBlock'().__depth+1, me,
                    'invalid access from `thread´')
        end

        if AST.iter'BlockI'() then
            CLS().has_pre = true   -- code for pre (before constr)

            -- new, spawn, async, await
            ASR(fr.tag ~= 'Ref',
                me, 'not permitted inside an interface')
        end

        if to.tag=='Var' and to.var.id=='_ret' then
            PROPS.has_ret = true
        end
    end,

--[[
    Var = function (me)
        local thr = AST.par(me, 'Thread')
        if thr then
            ASR(AST.iter'RefVarList'() or        -- param list
                me.ret or                         -- var assigned on return
                thr.__depth < me.var.blk.__depth, -- var is declared inside
                    me, 'invalid access from `thread´')
        end
    end,
]]

    Op1_cast = function (me)
        local tp, _ = unpack(me)
        if tp.ptr>0 and ENV.clss[tp.id] then
            PROPS.has_ifcs = true      -- cast must check org->cls_id
        end
    end,

    Lua = function (me)
        PROPS.has_lua = true
    end,
}

AST.visit(F)
