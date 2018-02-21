defmodule Acceptor do
    def start() do
        ballotNumber = {}
        accepted = MapSet.new()
        IO.puts("acceptor#{inspect self()} online")
        body(ballotNumber, accepted)
    end

    # param ballotNumber : ballot [the most recent ballot]
    # param accepted : mapset [the accepted pvalues]
    def body(ballotNumber, accepted) do
        receive do
            {:p1a, {src, ballotNumber_}} ->
                ballotNumber = 
                    if ballotNumber_ > ballotNumber do
                        ballotNumber_
                    else
                        ballotNumber
                    end
                send src, {:p1b, {self(), ballotNumber, accepted}}
                body(ballotNumber, accepted)
            
            {:p2a, {src, ballotNumber_, slotNumber, command}} ->
                accepted =
                    if ballotNumber_ == ballotNumber do
                        # only accept the pvalue if it is for the current ballot number
                        pvalue = {ballotNumber_, slotNumber, command}
                        MapSet.put(accepted, pvalue)
                    else
                        accepted
                    end
                send src, {:p2b, {self(), ballotNumber, slotNumber}}
                body(ballotNumber, accepted)
        end
    end
end