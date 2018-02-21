defmodule Replica do

    @window 1

    def start(database, monitor, serverNum) do
        requests = []
        decisions = Map.new()
        proposals = Map.new()
        slotOut = slotIn = 1
        IO.puts("replica#{inspect self()} online")
        
        receive do
            {:initialConfig, config} ->
                # I think other modules are not online yet without this
                Process.sleep(1000)
                body(requests, decisions, proposals, slotOut, slotIn, config, database, monitor, serverNum)
        end
    end

    # param request : list
    # param decisions : map
    # param proposals : map
    # param slotOut : int
    # param slotIn : int
    # param config : {[], [], []}
    def body(requests, decisions, proposals, slotOut, slotIn, config, database, monitor, serverNum) do
        {requests, decisions, proposals, slotOut} = 
            receive do
                {:command, command} ->
                    # requests are sent to the monitor and added to the list
                    send monitor, {:client_request, serverNum}
                    {[command | requests], decisions, proposals, slotOut}

                {:decision, {_src, slotNumber, command}} ->
                    # decisions are added, then executed
                    decisions = Map.put(decisions, slotNumber, command)
                    {requests, proposals, slotOut} = appendProposals(requests, decisions, proposals, slotOut, database)
                    {requests, decisions, proposals, slotOut}
            end
        
        # after receiving a message, propose
        {proposals, config, requests, slotIn} = propose(requests, decisions, proposals, slotOut, slotIn, config)
        body(requests, decisions, proposals, slotOut, slotIn, config, database, monitor, serverNum)
    end

    # param requests : list
    # param decisions : map
    # param slotOut : int
    # param slotIn : int

    # returns {proposals : map, config : {[], [], []}, requests : list, slotIn : int}
    def propose(requests, decisions, proposals, slotOut, slotIn, config) do
        if length(requests) != 0 and slotIn < slotOut + @window do
            # check for reconfigCommand
            config = 
                if slotIn > @window and Map.has_key?(decisions, slotIn - @window) and
                elem(Map.get(decisions, slotIn - @window), 0) == :reconfigCommand do
                        {:reconfigCommand, {_client, _requestId, configMessage}} = Map.get(decisions, slotIn - @window)
                        {:config, config} = configMessage
                        config
                else
                        config
                end

            {proposals, requests} = 
                if not Map.has_key?(decisions, slotIn) do
                    # get the oldest requests (requests are added at index 0)
                    {command, requests} = List.pop_at(requests, length(requests) - 1)
                    

                    # add the command to the proposed ones
                    proposals = Map.put(proposals, slotIn, command)
                    {_replicas, _acceptors, leaders} = config

                    # propose the command with every leader
                    for leader <- leaders do
                        send leader, {:propose, {self(), slotIn, command}}
                    end
                    {proposals, requests}
                else
                    {proposals, requests}
                end
            # repeat
            propose(requests, decisions, proposals, slotOut, slotIn + 1, config)
        else
            {proposals, config, requests, slotIn}
        end
    end

    # param requests : list
    # param decisions : map
    # param proposals : map 
    # param slotOut : int

    # returns {requests : list, proposals : map, slotOut : int}
    def appendProposals(requests, decisions, proposals, slotOut, database) do
        # if there is a decision for the current slot out
        if Map.has_key?(decisions, slotOut) do
            {requests, proposals} = 
                #if this replcia proposed something for that slot
                if Map.has_key?(proposals, slotOut) do
                    requests = 
                        # if it was not the same command, add it to requests to be proposed again
                        if Map.get(proposals, slotOut) != Map.get(decisions, slotOut) do
                            [Map.get(proposals, slotOut) | requests]
                        else
                            requests
                        end
                    {requests, Map.delete(proposals, slotOut)}
                else
                    {requests, proposals}
                end
            # do that action
            slotOut = perform(decisions, slotOut, Map.get(decisions, slotOut), database)

            #repeat
            appendProposals(requests, decisions, proposals, slotOut, database)
        else
            {requests, proposals, slotOut}
        end
    end

    # param decisions : map
    # param slotOut : int
    # param command : command

    # returns {slotOut : int}
    def perform(decisions, slotOut, command, database) do
        # check if the decided action has already been done
        {slotOut, return?} = done?(decisions, slotOut, command, 1)
        if return? do
            slotOut 
        else
            # skip reconfiguration, already done
            if elem(command, 0) == :reconfigCommand do
                slotOut + 1
            else    
                # ask the db to execute the transaction

                #IO.puts("\n#{Time.utc_now()} : replica#{inspect self()} : perform #{inspect slotOut} : #{inspect command}")
                {_src, _sent, transaction} = command
                send database, {:execute, transaction}
                slotOut + 1
            end
        end
    end

    # param decisions : map
    # param slotOut : int
    # param command : command
    # param s : int

    # returns {slotOut : int, done? : bool} done == true if the action has already been done
    def done?(decisions, slotOut, command, s) do
        # for all the past decisions
        if s < slotOut do
            # if this command was executed in a previous slot return true
            if Map.get(decisions, s) == command do
                {slotOut + 1, true}
            else
                done?(decisions, slotOut, command, s + 1)
            end
        else
            {slotOut, false}
        end
    end
    
end