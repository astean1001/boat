mylib = require "mylib"

------------------------------------------------------------------------------------

_G.Config={
    -- 투표이름
    title = "성민이는 살아있을까?",
    -- 관리자 주소
    oracle = "wZMWYtLQZcfyoQUJVqWKScoLgKrbLEfc2H",
    -- 개최자 주소
    opener = "wZMWYtLQZcfyoQUJVqWKScoLgKrbLEfc2H",
    -- 시작 블록
    startAt = 3,
    -- 기간 블록 수
    blockCount = 86400,
    -- 표값
    votePrice = 0,
    -- 찬성표
    yayVote = 0,
    -- 반대표
    nayVote = 0,
    -- 투표 상태
    status = 1,
    -- 투표 결과
    result = 0
}

------------------------------------------------------------------------------------

_G.LibHelp={
    StandardKey={
        title = "title",
        oracle = "oracle",
        opener = "opener",
        startAt = "startAt",
        blockCount = "blockCount",
        votePrice = "votePrice",
        yayVote = "yayVote",
        nayVote = "nayVote",
        status = "status",
        result = "result",
    },
    OP_TYPE = {
        ADD_FREE = 1,
        SUB_FREE = 2
    },
    WriteAccountData = function (opType, addrType, accountIdTbl, moneyTbl)
        local writeOutputTbl = {
            addrType = addrType,
            accountIdTbl = accountIdTbl,
            operatorType = opType,
            outHeight = 0,
            moneyTbl = moneyTbl
        }
        assert(mylib.WriteOutput(writeOutputTbl),"WriteAccountData" .. opType .. " err")
    end,
    TableIsNotEmpty = function (t)
        return _G.next(t) ~= nil
    end,
    Unpack = function (t,i)
        i = i or 1
        if t[i] then
          return t[i], _G.LibHelp.Unpack(t,i+1)
        end
    end,
    LogMsg = function (msg)
        local logTable = {
             key = 0,
             length = string.len(msg),
             value = msg
       }
       _G.mylib.LogPrint(logTable)
    end,
    GetContractValue = function (key)
        assert(#key > 0, "Key is empty")
        local tValue = { _G.mylib.ReadData(key) }
        if _G.LibHelp.TableIsNotEmpty(tValue) then
          return true,tValue
        else
            _G.LibHelp.LogMsg("Key not exist")
          return false,nil
        end
    end,
    GetCurrTxAccountAddress = function ()
        return {_G.mylib.GetBase58Addr(_G.mylib.GetCurTxAccount())}
    end,
    GetContractTxParam = function (startIndex, length)
        assert(startIndex > 0, "GetContractTxParam start error(<=0).")
        assert(length > 0, "GetContractTxParam length error(<=0).")
        assert(startIndex+length-1 <= #_G.contract, "GetContractTxParam length ".. length .." exceeds limit: " .. #_G.contract)
        local newTbl = {}
        for i = 1,length do
          newTbl[i] = _G.contract[startIndex+i-1]
        end
        return newTbl
    end,
    TransferToAddr = function (addrType, accTbl, moneyTbl)
        assert(TableIsNotEmpty(accTbl), "WriteWithdrawal accTbl empty")
        assert(TableIsNotEmpty(moneyTbl), "WriteWithdrawal moneyTbl empty")
        WriteAccountData(OP_TYPE.ADD_FREE, addrType, accTbl, moneyTbl)
        local appRegId = {mylib.GetScriptID()}
        WriteAccountData(OP_TYPE.SUB_FREE, ADDR_TYPE.REGID, appRegId, moneyTbl)
        return true
    end,
    Serialize = function(obj, hex)
        local lua = ""
        local t = type(obj)

        if t == "table" then
            for i=1, #obj do
                if hex == false then
                    lua = lua .. string.format("%c",obj[i])
                elseif hex == true then
                    lua = lua .. string.format("%02x",obj[i])
                else
                    error("index type error.")  
                end
            end
        elseif t == "nil" then
            return nil
        else
            error("can not Serialize a " .. t .. " type.")
        end

        return lua
    end
}

_G.Vote={
    TX_TYPE =
    {
        INTIALIZE = 0x15,
        SET_POSITION = 0x16,
        VOTE_RESULT = 0x17,
        PAYOFF = 0x18,
    },
    VOTE_TYPE = 
    {
        YAY = 0x01,
        NAY = 0x02,
    },
    Config=function ()
        local nowstamp = _G.mylib.GetBlockTimestamp(0)
        -- 투표 상태 조회
        assert(_G.LibHelp.GetContractValue("status")==false,"Already configured")
        -- write down standard key
        for k,v in pairs(_G.LibHelp.StandardKey) do
            if _G.Config[k] then
                local value = {}
                if _G.Config[k] == 3 then
                    value = {_G.mylib.IntegerToByte8(nowstamp)}
                elseif type(_G.Config[k]) ==  "number" and _G.Config[k] ~= 3 then
                    value = {_G.mylib.IntegerToByte8(_G.Config[k])}
                else
                    value = {string.byte(_G.Config[k],1,string.len(_G.Config[k])) }
                end
                local writeVoteTable = {
                    key = v,
                    length = #value,
                    value = value
                }
                assert(_G.mylib.WriteData(writeVoteTable),'can not issue vote, failed to write the key='..v..' value='.._G.Config[k])
            else
                error('can not issue vote, failed to read the key='..k)
            end
        end
        _G.LibHelp.LogMsg("vote contract config success, title: ".._G.Config.title.."issuer: ".._G.Config.opener)
    end,
    Position=function (votes, position)
        assert(votes > 0, "Position start error(<=0).")
        assert(_G.Config.status == 1, "Position start error(Vote Status Ended).")
        local nowstamp = _G.mylib.GetBlockTimestamp(0)
        local dummy = false
        local start = 0 
        dummy, start = _G.LibHelp.GetContractValue("startAt")
        assert((_G.mylib.ByteToInteger(_G.LibHelp.Unpack(start)) + _G.Config.blockCount) >= nowstamp, "Position start error(Vote Time Expired).")
        assert(position < 3, "Position start error(invaild vote type).")
        local value = _G.mylib.GetCurTxPayAmount()
        assert((votes*_G.Config.votePrice) == value, "Position start error(insufficient vote price).")

        local myval = 0;
        local writeVotes = {};
        local voteval = 0;
        local writeVoteVal = {};
        local addr_pre = _G.mylib.GetCurTxAccount()
        local addr = _G.LibHelp.Serialize({_G.mylib.GetBase58Addr(_G.LibHelp.Unpack(addr_pre))}, false)

        if position == _G.Vote.VOTE_TYPE.YAY then
            if _G.LibHelp.GetContractValue("YAY"..addr)~=false then
                dummy, myval = _G.LibHelp.GetContractValue("YAY" .. _G.mylib.GetCurTxAccount())
                myval = {_G.mylib.IntegerToByte8(_G.mylib.ByteToInteger(_G.LibHelp.Unpack(myval))+votes)}
                writeVotes = {
                    key = "YAY" .. addr,
                    length = #myval,
                    value = myval
                }
            else
                myval = {_G.mylib.IntegerToByte8(0+votes)}
                writeVotes = {
                    key = "YAY" .. addr,
                    length = #myval,
                    value = myval
                }
            end
            dummy, voteval = _G.LibHelp.GetContractValue("yayVote")
            voteval = {_G.mylib.IntegerToByte8(_G.mylib.ByteToInteger(_G.LibHelp.Unpack(voteval))+votes)}
            writeVoteVal = {
                key = "yayVote",
                length = #voteval,
                value = voteval
            }
            assert(_G.mylib.WriteData(writeVoteVal),'FAILED TO WRITE VOTE PROCESS')
        else
            if _G.LibHelp.GetContractValue("NAY"..addr)~=false then
                dummy, myval = _G.LibHelp.GetContractValue("NAY" .. addr)
                myval = {_G.mylib.IntegerToByte8(_G.mylib.ByteToInteger(_G.LibHelp.Unpack(myval))+votes)}
                writeVotes = {
                    key = "NAY" .. addr,
                    length = #myval,
                    value = myval
                }
            else
                myval = {_G.mylib.IntegerToByte8(0+votes)}
                writeVotes = {
                    key = "NAY" .. addr,
                    length = #myval,
                    value = myval
                }
            end
            dummy, voteval = _G.LibHelp.GetContractValue("nayVote")
            voteval = {_G.mylib.IntegerToByte8(_G.mylib.ByteToInteger(_G.LibHelp.Unpack(voteval))+votes)}
            writeVoteVal = {
                key = "nayVote",
                length = #voteval,
                value = voteval
            }
            assert(_G.mylib.WriteData(writeVoteVal),'FAILED TO WRITE VOTE PROCESS')
        end
    end,
    Result=function(result)
        local oracle_pre = {_G.mylib.GetCurTxAccount()}
        local oracle = _G.LibHelp.Serialize({_G.mylib.GetBase58Addr(_G.LibHelp.Unpack(oracle_pre))}, false)

        assert(_G.Config.oracle == oracle, 'Set Result Failed (Only Oracle)')
        assert((result == _G.Vote.VOTE_TYPE.YAY) or (result == _G.Vote.VOTE_TYPE.NAY), "Set Result Failed (invaild result type).")
        local writeResultVal = {
            key = "result",
            length = 1,
            value = {result}
        }
        local writeStatVal = {
            key = "status",
            length = 1,
            value = {2}
        }
        assert(_G.mylib.WriteData(writeResultVal),'Set Result Failed (writeResultVal)')
        assert(_G.mylib.WriteData(writeStatVal),'Set Result Failed (writeStatVal)')
    end,
    Payoff=function()
        local player = _G.mylib.GetCurTxAccount()
        assert(_G.LibHelp.GetContractValue("NAY".._G.mylib.GetCurTxAccount())~=false or _G.LibHelp.GetContractValue("YAY".._G.mylib.GetCurTxAccount())~=false, "Pay Off Failed (No Voting)")
        local nowstamp = _G.mylib.GetBlockTimestamp(0)
        local nowstamp = _G.mylib.GetBlockTimestamp(0)
        local dummy = false
        local start = 0 
        dummy, start = _G.LibHelp.GetContractValue("startAt")
        assert(tonumber(_G.LibHelp.Serialize(start, true),16) + _G.Config.blockCount < nowstamp, "Pay Off Failed (Vote Not Ended)")
        local result = _G.LibHelp.GetContractValue("result")
        local yayval = _G.LibHelp.GetContractValue("yayVote")
        local nayval = _G.LibHelp.GetContractValue("nayVote")
        local myvotes = 0
        local sendAmt = 0
        local base58_addrTbl = _G.LibHelp.GetCurrTxAccountAddress()
        if player == (_G.Config.oracle or _G.Config.opener) then
            sendAmt = _G.mylib.IntegerToByte8(_G.Config.votePrice * nayval / yayval * 0.01)
            _G.LibHelp.TransferToAddr(_G.LibHelp.ADDR_TYPE.BASE58,base58_addrTbl,sendAmt)
        elseif result == _G.Vote.VOTE_TYPE.YAY then
            assert(_G.LibHelp.GetContractValue("YAY".._G.mylib.GetCurTxAccount())~=false, "Pay Off Failed (No Successful Bet)")
            myvotes = _G.LibHelp.GetContractValue("YAY".._G.mylib.GetCurTxAccount())
            sendAmt = _G.mylib.IntegerToByte8((_G.Config.votePrice * nayval / yayval * 0.98) * myvotes)
            _G.LibHelp.TransferToAddr(_G.LibHelp.ADDR_TYPE.BASE58,base58_addrTbl,sendAmt)
        else
            assert(_G.LibHelp.GetContractValue("NAY".._G.mylib.GetCurTxAccount())~=false, "Pay Off Failed (No Successful Bet)")
            myvotes = _G.LibHelp.GetContractValue("NAY".._G.mylib.GetCurTxAccount())
            sendAmt = _G.mylib.IntegerToByte8((_G.Config.votePrice * yayval / nayval * 0.98) * myvotes)
            _G.LibHelp.TransferToAddr(_G.LibHelp.ADDR_TYPE.BASE58,base58_addrTbl,sendAmt)
        end
    end
}

------------------------------------------------------------------------------------

assert(_G.contract[1] == 0xf0, "Parameter MagicNo error (~=0xf0): " .. _G.contract[1])

if _G.contract[2] == _G.Vote.TX_TYPE.INTIALIZE then
    _G.Vote.Config()
elseif _G.contract[2] == _G.Vote.TX_TYPE.SET_POSITION and #_G.contract==11 then
    local pos = 2
    local position = _G.contract[3]
    pos = pos + 2
    local votes = _G.mylib.ByteToInteger(_G.LibHelp.Unpack(_G.LibHelp.GetContractTxParam(pos, 8)))
    _G.Vote.Position(votes,position)
elseif _G.contract[2] == _G.Vote.TX_TYPE.VOTE_RESULT and #_G.contract==3 then
    local pos = 3
    local result = _G.contract[3]
    _G.Vote.Result(result)
elseif _G.contract[2] == _G.Vote.TX_TYPE.PAYOFF then
    _G.Vote.Payoff()
else
    error(string.format("Method %02x not found or parameter error", _G.contract[2]))
end
