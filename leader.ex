defmodule Leader do

    # param config : config
    def start() do
        ballotNumber = {0, self()}
        active = false
        proposals = Map.new()

        receive do
            {:initialConfig, config} ->
                body(proposals, ballotNumber, config, active)
        end
    end

    # param proposals : map
    # param ballotNumber : int
    # param config : config
    # param active : bool
    def body(proposals, ballotNumber, config, active) do
        IO.puts("leader#{inspect self()} online")
        {_replicas, acceptors, _leaders} = config

        # spawn the first scout
        Node.spawn(Node.self(), Scout, :start, 
            [self(), acceptors, ballotNumber])

        talk(proposals, ballotNumber, config, active)
    end

    # param proposals : map
    # param ballotNumber : int
    # param config : config
    # param active : bool
    def talk(proposals, ballotNumber, config, active) do
        receive do
            {:propose, {_src, slotNumber, command}} ->
                proposals = 
                    if not Map.has_key?(proposals, slotNumber) do
                        proposals = Map.put(proposals, slotNumber, command)
                        # if a new proposals arrive spawn a commander
                        # it will try to make the proposal accepted by acceptors
                        if active do
                            {replicas, acceptors, _leaders} = config
                            Node.spawn(Node.self(), Commander, :start,
                                [self(), acceptors, replicas, 
                                ballotNumber, slotNumber, command])
                        end
                        proposals
                    else
                        proposals
                    end
                talk(proposals, ballotNumber, config, active)
            
            {:adopted, {_src, ballotNumber_, accepted}} ->
                # a scout found that 
                # ballotNumber_ has been adopted by a majority of acceptors
                {proposals, active} =
                    if ballotNumber == ballotNumber_ do
                        # only relevant for current ballot
                        
                        pmax = Map.new()
                        # update the proposals using the accepted set just received
                        proposals = processAccepted(proposals, MapSet.to_list(accepted), pmax)
                        
                        {replicas, acceptors, _leaders} = config
                        for {slotNumber, command} <- proposals do
                            # spawn commanders for all proposals
                            Node.spawn(Node.self(), Commander, :start,
                            [self(), acceptors, replicas,
                            ballotNumber, slotNumber, command])
                        end
                        active = true
                        {proposals, active}
                    else
                        {proposals, active}
                    end
                talk(proposals, ballotNumber, config, active)

            {:preempted, {_src, ballotNumber_}} ->
                # a newer ballot number has been discovered by a Scout or Commander
                ballotNumber =
                    if ballotNumber_ > ballotNumber do
                        # if it is newer than the local ballot number
                        {msgBallotNumberRound, _} = ballotNumber_
                        ballotNumber = {msgBallotNumberRound + 1, self()}
                        {_replicas, acceptors, _leaders} = config

                        # spawn a Scout to run phase 1 with a even newer ballot number
                        # it will try to find out which is the newest ballot number
                        Node.spawn(Node.self(), Scout, :start, 
                            [self(), acceptors, ballotNumber])
                        ballotNumber
                    else
                        ballotNumber
                    end
                # stop making new ballots and await for the accepted message
                active = false
                talk(proposals, ballotNumber, config, active)
            
            true ->
                IO.puts("leader#{inspect self()}: unknown message type")
                talk(proposals, ballotNumber, config, active)
        end
    end

    # param proposals : map
    # param accepted : list
    # param pmax : map

    # returns proposals : map
    def processAccepted(proposals, accepted, pmax) do
        # pmax tracks the latest pvalue for each ballot number

        # while there are proposals
        if length(accepted) > 0 do
            {{pvBallotNumber, slotNumber, command}, accepted} = List.pop_at(accepted, 0)
            {proposals, pmax} =
                if (not Map.has_key?(pmax, slotNumber))
                    or Map.get(pmax, slotNumber) < pvBallotNumber do
                    # if there is no pvalue recorded or a newer one is found add
                    # its ballot number to pmax, and
                    # its command to the proposals 
                    pmax = Map.put(pmax, slotNumber, pvBallotNumber)
                    proposals = Map.put(proposals, slotNumber, command)
                    {proposals, pmax}
                else
                    {proposals, pmax}
                end
            processAccepted(proposals, accepted, pmax)
        else
            proposals
        end
    end
end
