import POMDPs
using POMDPs: POMDP
using POMDPTools: Deterministic, Uniform, SparseCat, DiscreteBelief, DiscreteUpdater
using Plots
numChallenges = [0, 0, 0, 0, 0]


##### Struct for a bid
struct Bid
    quantity::Int
    face_value::Int
end

##### Define state structure
mutable struct LDState
    players::Array{T} where T<:POMDP{LDState, Bid, Int} # Vector of players
    players_dice::Array{Array{Int,1}} # Vector of players, each containing their dice
    players_6s::Array{Int} # Vector of players, containing an integer of number of 1/6s they have
    turn::Int # Current player's turn
    prevTurn::Int # Previous player's turn
    current_bid::Bid # Current bid
    total_dice::Int # Total number of dice on the table
end

##### State Initializer
function init_state(players::Array{T}, num_players::Int, num_dice::Array{Int}, turn = rand(1:num_players)) where T<:POMDP{LDState, Bid, Int}
    players_dice = [roll_dice(num_dice[i]) for i in 1:num_players] # Roll dice for each player
    players_6s = [count_1_6(players_dice[i]) for i in 1:num_players] # Count number of 1/6s for each player
    prevTurn = turn
    current_bid = Bid(0, 0)
    total_dice = sum(num_dice)

    # Initialize the belief of any POMDP players
    for i in 1:num_players
        if isa(players[i], POMDPPlayer)
            players[i] = initial_belief(players[i], num_players, num_dice)
        end
    end
    # count how many players actually have dice
    playersIn = 0
    for i in 1:num_players
        if length(players_dice[i]) > 0
            playersIn += 1
        end
    end
    # # print some relavent information to the user and wait for a enter
    # print("\033[2J")
    # print("\033[0;0H")
    # println("Round Initalized with ", playersIn, " players and ", total_dice, " dice.")
    # println("Press enter to continue")
    # readline()
    return LDState(players, players_dice, players_6s, turn, prevTurn, current_bid, total_dice)
end

##### Game helper functions:
# Roll dice
function roll_dice(num_dice::Int)
    return [rand(1:6) for _ in 1:num_dice]
end
# Get number of 1/6s
function count_1_6(dice::Array{Int,1})
    return count(x->x==6, dice) + count(x->x==1, dice)
end
# Increase bid quantity by 1
function make_bid(state::LDState)
    quantity = state.current_bid.quantity + 1
    face_value = 6
    new_bid = Bid(quantity, face_value)
    state.current_bid = new_bid
    return state
end
# Challenge
function challenge(state::LDState)
    # Clear screen
    # print("\033[2J")
    # print("\033[0;0H")
    # println("Challenge by Player ", state.turn, "!") 
    # println("Current bid: ", state.current_bid.quantity, " ", state.current_bid.face_value)
    # println("All dice on the table: ")
    total = 0
    for i in 1:length(state.players)
        # # println("Player ", i, ": [", join(state.players_dice[i], ", "), "]")
        total += count_1_6(state.players_dice[i])
    end
    # # println("Total # of 1/6s: ", total)
    if state.current_bid.quantity > total
        # # println("Challenge successful!")
        return true
    else
        # # println("Challenge failed!")
        return false
    end
end
# Function to cause a player to lose a dice
function lose_dice(state::LDState, loser::Int)
    # println("Player ", loser, " loses a dice!")
    
    num_dice = [length(state.players_dice[i]) for i in 1:length(state.players_dice)]
    num_players = length(state.players)
    # Remove a dice from the player
    num_dice[loser] -= 1

    # Check if the player is out of dice
    if num_dice[loser] == 0
        # println("Player ", loser, " is out of dice!")
        # Keep player in game, they just have zero dice! Set their playerNum to be -1
        state.players[loser].playerNum = -1
    end

    # println("Press enter to continue")
    # readline()
    # Reinitalize the state
    return init_state(state.players, num_players, num_dice, loser) 
    # return init_state(state.players, num_players, num_dice) 
end
# Returns True if there is only one player with dice left
function onePlayerLeft(state::LDState)
    num_dice = [length(state.players_dice[i]) for i in 1:length(state.players_dice)]
    num_players = length(state.players)
    count = 0
    for i in 1:num_players
        if num_dice[i] > 0
            count += 1
        end
    end
    return count == 1
end
# Helper function to normalize the belief
function normalize_belief(sparse_cat::SparseCat)
    total_prob = sum(sparse_cat.probs)
    categories = sparse_cat.vals
    normalized_probs = sparse_cat.probs ./ total_prob
    return SparseCat(categories, normalized_probs)
end

##### Define a manual player
mutable struct ManualPlayer <: POMDP{LDState, Bid, Int}
    playerNum::Int
end

##### Define a MDP player
mutable struct MDPPlayer <: POMDP{LDState, Bid, Int}
    playerNum::Int
    bluffingProb::Float64
end

##### Define a POMDP player
mutable struct POMDPPlayer <: POMDP{LDState, Bid, Int}
    playerNum::Int
    belief_space::Array{SparseCat{Array{Int64, 1}, Array{Float64, 1}}, 1} # Array of players, where in each element is a SparseCat belief of number of 1/6s (int64) and probability (float64)
end

#### MANUAL PLAYER ACTION, return 1 for bid, 0 for challenge
function POMDPs.action(p::ManualPlayer, s::LDState)
    # println("Player ", p.playerNum, " it is your turn.")
    # println("Your dice: ", s.players_dice[p.playerNum])
    # println("Your # 1/6s: ", s.players_6s[p.playerNum])
    # println("Current bid: ", s.current_bid.quantity, " ", s.current_bid.face_value)
    # println("Do you want to make a bid or challenge? (b/c)")
    a = # readline()
    if a == "b"
        return 1
    else
        return 0
    end
end

#### MDP PLAYER ACTION, return 1 for bid, 0 for challenge
function POMDPs.action(p::MDPPlayer, s::LDState)
    # Get your number of 1/6s
    self_1_6 = s.players_6s[p.playerNum]
    # Get the current bid quantity
    bid_quantity = s.current_bid.quantity

    # Get the total number of dice on table, not including your own
    otherDice = s.total_dice - length(s.players_dice[p.playerNum])

    # Use 1/3 rule
    estimateNum = otherDice / 3 + self_1_6

    # If the quantity of the bid is greater than the estimate, challenge
    if estimateNum < bid_quantity
        # println("Player ", p.playerNum, " challenges!")
        # println("Press enter to continue")
        # readline() 
        if rand() < p.bluffingProb # % chance to bluff and bid instead of challenge
            return 1
        else
            return 0
        end
    else
        # println("Player ", p.playerNum, " bids!")
        # println("Press enter to continue")
        # readline()
        return 1
    end
end

#### POMDP PLAYER ACTION, return 1 for bid, 0 for challenge
function POMDPs.action(p::POMDPPlayer, s::LDState)
    # For the action, sum the probabilities of the belief space for each player
    
    # Get the current bid quantity
    bid_quantity = s.current_bid.quantity
    # Get the 1/6s that POMDP player has
    self_1_6 = s.players_6s[p.playerNum]
    totalEstimate = self_1_6

    # For all other players, loop through the belief state for that player
    for i in 1:length(s.players)
        # If not yourself and player isnt out of the game
        if i != p.playerNum 
            # Get the belief space for that player
            belief = p.belief_space[i]
            
            # Multiply the probability by the number of 1/6s for each category
            # sum probs and vals
            estimate = 0
            for i in 1:length(belief.vals)
                estimate += belief.vals[i] * belief.probs[i]
            end     
            totalEstimate += estimate
        end
    end
    # now compare totalEstimate to bid_quantity
    if totalEstimate < bid_quantity
        # println("Player ", p.playerNum, " challenges!")
        # println("Press enter to continue")
        # readline()
        return 0
    else
        # println("Player ", p.playerNum, " bids!")
        # println("Press enter to continue")
        # readline()
        return 1
    end
end

#### BELIEF INITIALIZER ####
function initial_belief(p, numPlayer, numDice)
    belief::Array{SparseCat{Array{Int64, 1}, Array{Float64, 1}}, 1} = []
    for i in 1:numPlayer
        # adjust the belief space to only contain numbers between 0 and the number of dice
        categories = [i for i in 0:numDice[i]]
        # To get the probabilties, sample 1000 dice rolls and get the number of 1/6s
        probabilities = [0 for _ in 0:numDice[i]]
        for j in 1:1000
            dice_roll = roll_dice(numDice[i])
            num_1_6s = count_1_6(dice_roll)
            # Add 1 to the index associated with the number of 1/6s
            probabilities[num_1_6s+1] += 1
        end
        # Normalize the probabilities
        probabilities = probabilities ./ sum(probabilities)
        push!(belief, SparseCat(categories, probabilities))
    end
    p.belief_space = belief
    return p
end

#### POMDP BELIEF UPDATE ####
# Observation is the index of the player who made the bid
function POMDPs.update(p::POMDPPlayer, s::LDState, a::Bid, o::Int)

    # Get the current bid quantity
    bid_quantity = s.current_bid.quantity

    # Get the # of dice the player who made the bid has
    dice_player = length(s.players_dice[o])
    # println("Player ", o, " has ", dice_player, " dice.")

    # Get the total # of dice on the table
    dice_total = s.total_dice

    # Other dice on the table
    other_dice = dice_total - dice_player

    # Use particle filter, aka only update belifs of actions that a MDP player would take, using 1/3 rule
    # Sample 1000 particles
    numParticles = 1000
    probs = [0 for _ in 0:dice_player]
    trans_prob = [0 for _ in 0:dice_player]
    particleInject = 0.05
    for i in 1:numParticles
        # Sample a dice roll_dice
        dice_roll = roll_dice(dice_player)
        # Get the number of 1/6s
        num_1_6s = count_1_6(dice_roll)
        # Keep track of transition probability
        trans_prob[num_1_6s+1] += 1
        # Use 1/3 rule
        estimateNum = other_dice / 3 + num_1_6s
        # Check if the observation, them betting, aligns with their assume policy, 1/3 rule
        if estimateNum < bid_quantity
            # Player would challenge, ignore, particle filter
            # PARTICLE INJECTION:
            # if rand() < particleInject
            #     probs[num_1_6s+1] += 1
            # else
            #     continue
            # end
            continue
        else
            # Player would bid, update probabilities
            probs[num_1_6s+1] += 1
        end
    end
    # Now do believe update, normalize the probabilities, factor in transition probability too
    # Normalize the transition probability
    trans_prob = trans_prob ./ sum(trans_prob)
    if sum(probs) != 0
        probs = probs ./ sum(probs)
        probs = probs .* trans_prob # factor in transition probability?
    else
        probs = trans_prob
    end
    
    # Should we just add the probabilities? or how best to do this?
    # I think multiplying in the probabilities is correct according to particle filter
    new_belief = SparseCat(p.belief_space[o].vals, p.belief_space[o].probs .* probs)

    # now normalize the new belief
    new_belief = normalize_belief(new_belief)

    # Update the belief space
    p.belief_space[o] = new_belief

    return p
end

#### Play the game
function play_liars_dice(state::LDState)
    
    winner = -1
    # Loop through the game
    while true

        # Clear the screen
        # print("\033[2J")
        # print("\033[0;0H")

        # println("Current bid: ", state.current_bid.quantity, " ", state.current_bid.face_value)
        player = state.players[state.turn]
        # Check if the player is out of dice
        if player.playerNum == -1
            state.turn = mod(state.turn, length(state.players)) + 1
            continue
        end

        # ORIGINAL
        # Check to see if there is only one player left
        if onePlayerLeft(state)
            # println("Player ", state.turn, " wins!")
            winner = player.playerNum
            return winner
        end
        
        # Get the action
        action = POMDPs.action(player, state)
        if action == 1
            state = make_bid(state) # Increase bid
        else
            # keep track of which player challenged
            numChallenges[state.turn] += 1
            if challenge(state) # Challenge successful, original bidder loses a die
                state = lose_dice(state, state.prevTurn) # ORIGINAL
                # state = lose_dice(state, state.turn) # NEW WHERE CHALLENGER LOSES A DICE
            else # Challenge unsuccessful, challenger loses a die
                state = lose_dice(state, state.turn) # ORIGINAL
                # state = lose_dice(state, state.prevTurn) # NEW WHERE WINNER LOSES A DICE
            end
        end

        # loop through all players and for any pomdps, update their belief space
        for i in 1:length(state.players)
            if isa(state.players[i], POMDPPlayer)
                # Update the belief space for that player
                state.players[i] = POMDPs.update(state.players[i], state, state.current_bid, state.prevTurn)
            end
        end

        state.prevTurn = state.turn
        state.turn = mod(state.turn, length(state.players)) + 1
    end
end

# Lets initalize a basic game between a mdp and manual player
# num_player = 3
# num_dice = [4, 4, 4]
# players = [ManualPlayer(1), POMDPPlayer(2, []), POMDPPlayer(3, [])]
# state = init_state(players, num_player, num_dice)
# winner = play_liars_dice(state)
# display(winner)

##### BENCHMARKING #####

num_benchmark = 1000
dice = 5:10
stats = []
num_player = 2
winner_mat_pomdp = zeros(Int, num_player)

for k in dice
    num_dice = k*ones(Int,num_player)
    for i in 1:num_benchmark
        players_bench = [POMDPPlayer(1, []), MDPPlayer(2, 0)] 
        state = init_state(players_bench, num_player, num_dice)
        winner = play_liars_dice(state)
        winner_mat_pomdp[winner] += 1
        # every 100 games, # # print the progress
        if i % 100 == 0
            println("Progress: ", i, "/", num_benchmark)
        end
    end
    # display(winner_mat_pomdp)
    win_percent = (winner_mat_pomdp[1] / sum(winner_mat_pomdp))*100
    # display(win_percent)
    push!(stats,win_percent)
end

# Create bar chart
b1 = bar(dice, stats, xlabel="number of dice", ylabel="win %", title="POMDP vs MDP (1v1)", legend=:topleft, label="POMDP")
display(b1)