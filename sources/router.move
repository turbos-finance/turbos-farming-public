module turbos_farming::router {
    use turbos_farming::{
        config::{Self, AdminCap, GlobalConfig},
        pool::{Self, Pool, WrappedPositionNFT},
        rewarder::{Self, RewarderManager}
    };
    use sui::{clock::Clock, coin::{Self, Coin}, pay};
    use turbos_clmm::{
        pool::{Pool as CLMMPool, PoolRewardVault, Versioned},
        position_manager::Positions,
        position_nft::TurbosPositionNFT
    };

    public fun add_role(
        admin_cap: &AdminCap,
        global_config: &mut GlobalConfig,
        member: address,
        role: u8,
    ) {
        config::add_role(admin_cap, global_config, member, role);
    }

    public fun remove_role(
        admin_cap: &AdminCap,
        global_config: &mut GlobalConfig,
        member: address,
        role: u8,
    ) {
        config::remove_role(admin_cap, global_config, member, role);
    }

    public fun set_roles(
        admin_cap: &AdminCap,
        global_config: &mut GlobalConfig,
        member: address,
        roles: u128,
    ) {
        config::set_roles(admin_cap, global_config, member, roles);
    }

    public fun accumulated_position_rewards(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        wrapped_position_id: ID,
        clk: &Clock,
    ) {
        pool::accumulated_position_rewards(
            global_config,
            rewarder_manager,
            pool,
            wrapped_position_id,
            clk,
        );
    }

    public fun add_liquidity<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: &mut WrappedPositionNFT,
        coin_a: Coin<CoinA>,
        coin_b: Coin<CoinB>,
        amount_limit_a: u64,
        amount_limit_b: u64,
        delta_liquidity: u128,
        clk: &Clock,
        deadline: u64,
        ctx: &mut TxContext,
    ) {
        let (bal_a, bal_b) = pool::add_liquidity<CoinA, CoinB, FeeType>(
            global_config,
            rewarder_manager,
            pool,
            clmm_pool,
            positions,
            versioned,
            wrapped_position,
            coin_a,
            coin_b,
            amount_limit_a,
            amount_limit_b,
            delta_liquidity,
            clk,
            deadline,
            ctx,
        );
        send_coin<CoinA>(coin::from_balance<CoinA>(bal_a, ctx), tx_context::sender(ctx));
        send_coin<CoinB>(coin::from_balance<CoinB>(bal_b, ctx), tx_context::sender(ctx));
    }

    public fun add_liquidity_fix_coin<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: &mut WrappedPositionNFT,
        coin_a: Coin<CoinA>,
        coin_b: Coin<CoinB>,
        amount_a: u64,
        amount_b: u64,
        fix_amount_a: bool,
        clk: &Clock,
        deadline: u64,
        ctx: &mut TxContext,
    ) {
        let (bal_a, bal_b) = pool::add_liquidity_fix_coin<CoinA, CoinB, FeeType>(
            global_config,
            rewarder_manager,
            pool,
            clmm_pool,
            positions,
            versioned,
            wrapped_position,
            coin_a,
            coin_b,
            amount_a,
            amount_b,
            fix_amount_a,
            clk,
            deadline,
            ctx,
        );
        send_coin<CoinA>(coin::from_balance<CoinA>(bal_a, ctx), tx_context::sender(ctx));
        send_coin<CoinB>(coin::from_balance<CoinB>(bal_b, ctx), tx_context::sender(ctx));
    }

    public fun add_rewarder<RewarderCoin>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        allocate_point: u64,
        clk: &Clock,
        ctx: &TxContext,
    ) {
        pool::add_rewarder<RewarderCoin>(
            global_config,
            rewarder_manager,
            pool,
            allocate_point,
            clk,
            ctx,
        );
    }

    public fun collect_clmm_reward<RewardCoin, CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: &mut WrappedPositionNFT,
        vault: &mut PoolRewardVault<RewardCoin>,
        reward_index: u64,
        reward_coin: Coin<RewardCoin>,
        clk: &Clock,
        ctx: &mut TxContext,
    ) {
        send_coin<RewardCoin>(
            coin::from_balance<RewardCoin>(
                pool::collect_clmm_reward<RewardCoin, CoinA, CoinB, FeeType>(
                    global_config,
                    clmm_pool,
                    positions,
                    versioned,
                    wrapped_position,
                    vault,
                    reward_index,
                    reward_coin,
                    clk,
                    ctx,
                ),
                ctx,
            ),
            tx_context::sender(ctx),
        );
    }

    public fun collect_fee<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: &mut WrappedPositionNFT,
        clk: &Clock,
        ctx: &mut TxContext,
    ) {
        let (bal_a, bal_b) = pool::collect_fee<CoinA, CoinB, FeeType>(
            global_config,
            clmm_pool,
            positions,
            versioned,
            wrapped_position,
            clk,
            ctx,
        );
        send_coin<CoinA>(coin::from_balance<CoinA>(bal_a, ctx), tx_context::sender(ctx));
        send_coin<CoinB>(coin::from_balance<CoinB>(bal_b, ctx), tx_context::sender(ctx));
    }

    public fun create_pool<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        clmm_pool: &CLMMPool<CoinA, CoinB, FeeType>,
        effective_tick_lower: u32,
        effective_tick_upper: u32,
        sqrt_price: u128,
        ctx: &mut TxContext,
    ) {
        pool::create_pool<CoinA, CoinB, FeeType>(
            global_config,
            rewarder_manager,
            clmm_pool,
            turbos_clmm::i32::from_u32(effective_tick_lower),
            turbos_clmm::i32::from_u32(effective_tick_upper),
            sqrt_price,
            ctx,
        );
    }

    public fun deposit<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &CLMMPool<CoinA, CoinB, FeeType>,
        positions: &Positions,
        nft: TurbosPositionNFT,
        clk: &Clock,
        ctx: &mut TxContext,
    ): WrappedPositionNFT {
        pool::deposit<CoinA, CoinB, FeeType>(
            global_config,
            rewarder_manager,
            pool,
            clmm_pool,
            positions,
            nft,
            clk,
            ctx,
        )
    }

    public fun harvest<RewardCoin>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        wrapped_position: &mut WrappedPositionNFT,
        clk: &Clock,
        ctx: &mut TxContext,
    ): Coin<RewardCoin> {
        coin::from_balance<RewardCoin>(
            pool::harvest<RewardCoin>(
                global_config,
                rewarder_manager,
                pool,
                wrapped_position,
                clk,
            ),
            ctx,
        )
    }

    public fun remove_liquidity<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: &mut WrappedPositionNFT,
        delta_liquidity: u128,
        min_amount_a: u64,
        min_amount_b: u64,
        clk: &Clock,
        ctx: &mut TxContext,
    ) {
        let (bal_a, bal_b) = pool::remove_liquidity<CoinA, CoinB, FeeType>(
            global_config,
            rewarder_manager,
            pool,
            clmm_pool,
            positions,
            versioned,
            wrapped_position,
            delta_liquidity,
            min_amount_a,
            min_amount_b,
            clk,
            ctx,
        );
        send_coin<CoinA>(coin::from_balance<CoinA>(bal_a, ctx), tx_context::sender(ctx));
        send_coin<CoinB>(coin::from_balance<CoinB>(bal_b, ctx), tx_context::sender(ctx));
    }

    public fun close_position<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: WrappedPositionNFT,
        min_amount_a: u64,
        min_amount_b: u64,
        clk: &Clock,
        ctx: &mut TxContext,
    ) {
        let (bal_a, bal_b) = pool::close_position<CoinA, CoinB, FeeType>(
            global_config,
            rewarder_manager,
            pool,
            clmm_pool,
            positions,
            versioned,
            wrapped_position,
            min_amount_a,
            min_amount_b,
            clk,
            ctx,
        );
        send_coin<CoinA>(coin::from_balance<CoinA>(bal_a, ctx), tx_context::sender(ctx));
        send_coin<CoinB>(coin::from_balance<CoinB>(bal_b, ctx), tx_context::sender(ctx));
    }

    public fun update_effective_tick_range<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &CLMMPool<CoinA, CoinB, FeeType>,
        positions: &Positions,
        effective_tick_lower: u32,
        effective_tick_upper: u32,
        sqrt_price: u128,
        start: vector<ID>,
        limit: u64,
        clk: &Clock,
        ctx: &TxContext,
    ) {
        pool::update_effective_tick_range<CoinA, CoinB, FeeType>(
            global_config,
            rewarder_manager,
            pool,
            clmm_pool,
            positions,
            turbos_clmm::i32::from_u32(effective_tick_lower),
            turbos_clmm::i32::from_u32(effective_tick_upper),
            sqrt_price,
            start,
            limit,
            clk,
            ctx,
        );
    }

    public fun update_pool_allocate_point<RewardCoin>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &Pool,
        allocate_point: u64,
        clk: &Clock,
        ctx: &TxContext,
    ) {
        pool::update_pool_allocate_point<RewardCoin>(
            global_config,
            rewarder_manager,
            pool,
            allocate_point,
            clk,
            ctx,
        );
    }

    public fun withdraw(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        wrapped_position: WrappedPositionNFT,
        clk: &Clock,
        _ctx: &TxContext,
    ): TurbosPositionNFT {
        pool::withdraw(global_config, rewarder_manager, pool, wrapped_position, clk)
    }

    public fun create_rewarder<RewardCoin>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        emission_per_second: u128,
        clk: &Clock,
        ctx: &mut TxContext,
    ) {
        rewarder::create_rewarder<RewardCoin>(
            global_config,
            rewarder_manager,
            emission_per_second,
            clk,
            ctx,
        );
    }

    public fun deposit_rewarder<RewardCoin>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        coins: vector<Coin<RewardCoin>>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<RewardCoin> {
        let mut merged = merge_coins<RewardCoin>(coins, ctx);
        rewarder::deposit_rewarder<RewardCoin>(
            global_config,
            rewarder_manager,
            coin::into_balance<RewardCoin>(coin::split<RewardCoin>(&mut merged, amount, ctx)),
        );
        merged
    }

    public fun emergent_withdraw<RewardCoin>(
        admin_cap: &AdminCap,
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<RewardCoin> {
        coin::from_balance<RewardCoin>(
            rewarder::emergent_withdraw<RewardCoin>(
                admin_cap,
                global_config,
                rewarder_manager,
                amount,
            ),
            ctx,
        )
    }

    public fun update_rewarder<RewardCoin>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        emission_per_second: u128,
        clk: &Clock,
        ctx: &TxContext,
    ) {
        rewarder::update_rewarder<RewardCoin>(
            global_config,
            rewarder_manager,
            emission_per_second,
            clk,
            ctx,
        );
    }

    public fun merge_coins<T0>(mut coins: vector<Coin<T0>>, ctx: &mut TxContext): Coin<T0> {
        if (vector::is_empty<Coin<T0>>(&coins)) {
            vector::destroy_empty<Coin<T0>>(coins);
            coin::zero<T0>(ctx)
        } else {
            let mut first = vector::pop_back<Coin<T0>>(&mut coins);
            pay::join_vec<T0>(&mut first, coins);
            first
        }
    }

    public fun send_coin<T0>(coin: Coin<T0>, recipient: address) {
        if (coin::value<T0>(&coin) > 0) {
            transfer::public_transfer<Coin<T0>>(coin, recipient);
        } else {
            coin::destroy_zero<T0>(coin);
        };
    }
}
