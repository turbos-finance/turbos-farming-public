module turbos_farming::rewarder {
    use turbos_farming::{config::{Self}};
    use std::type_name::{Self, TypeName};
    use sui::{
        bag::{Self, Bag},
        balance::{Self, Balance},
        clock::Clock,
        event::emit,
        linked_table::{Self, LinkedTable},
        vec_map::{Self, VecMap}
    };
    use turbos_clmm::full_math_u128;

    const ACC_PRECISION: u256 = 1000000000000000000000000000000000000;
    const EHarvestExceedsReleased: u64 = 0;
    const ERewarderAlreadyExists: u64 = 1;
    const ERewarderNotExists: u64 = 2;
    const EPoolShareNotRegistered: u64 = 4;
    const EInsufficientVaultBalance: u64 = 5;
    const EPoolNotRegistered: u64 = 6;
    const EPoolAlreadyRegistered: u64 = 7;
    const EPoolNotInRewarder: u64 = 8;
    const EPoolAlreadyInRewarder: u64 = 9;

    public struct PoolRewarderInfo has store {
        allocate_point: u64,
        acc_per_share: u256,
        last_reward_time: u64,
        reward_released: u128,
        reward_harvested: u64,
    }

    public struct Rewarder has store {
        reward_coin: TypeName,
        total_allocate_point: u64,
        emission_per_second: u128,
        last_reward_time: u64,
        total_reward_released: u128,
        total_reward_harvested: u64,
        pools: LinkedTable<ID, PoolRewarderInfo>,
    }

    public struct RewarderManager has key, store {
        id: UID,
        vault: Bag,
        pool_shares: LinkedTable<ID, u128>,
        rewarders: LinkedTable<TypeName, Rewarder>,
    }

    public struct InitRewarderManagerEvent has copy, drop {
        id: ID,
    }

    public struct CreateRewarderEvent has copy, drop {
        reward_coin: TypeName,
        emission_per_second: u128,
    }

    public struct UpdateRewarderEvent has copy, drop {
        reward_coin: TypeName,
        emission_per_second: u128,
    }

    public struct DepositEvent has copy, drop {
        reward_type: TypeName,
        deposit_amount: u64,
        after_amount: u64,
    }

    public struct EmergentWithdrawEvent has copy, drop, store {
        reward_type: TypeName,
        withdraw_amount: u64,
        after_amount: u64,
    }

    fun accumulate_pool_reward(
        rewarder: &mut Rewarder,
        pool_id: ID,
        pool_share: u128,
        now: u64,
    ): u256 {
        let pool_info = linked_table::borrow_mut<ID, PoolRewarderInfo>(&mut rewarder.pools, pool_id);
        let last_reward_time = pool_info.last_reward_time;
        pool_info.last_reward_time = now;
        let should_skip = if (now <= last_reward_time) {
            true
        } else if (pool_info.allocate_point == 0) {
            true
        } else if (pool_share == 0) {
            true
        } else {
            rewarder.emission_per_second == 0
        };
        if (should_skip) {
            return pool_info.acc_per_share
        };
        let reward_delta =
            full_math_u128::full_mul(rewarder.emission_per_second, ((now - last_reward_time) as u128)) * (pool_info.allocate_point as u256) / (rewarder.total_allocate_point as u256);
        pool_info.reward_released = pool_info.reward_released + (reward_delta as u128);
        pool_info.acc_per_share = pool_info.acc_per_share + (reward_delta * ACC_PRECISION / (pool_share as u256));
        pool_info.acc_per_share
    }

    fun accumulate_pools_reward<RewardCoin>(rewarder_manager: &mut RewarderManager, now: u64) {
        let rewarder = linked_table::borrow_mut<TypeName, Rewarder>(
            &mut rewarder_manager.rewarders,
            type_name::with_defining_ids<RewardCoin>(),
        );
        let mut pool_cursor = *linked_table::front<ID, PoolRewarderInfo>(&rewarder.pools);
        while (option::is_some<ID>(&pool_cursor)) {
            let pool_id = *option::borrow<ID>(&pool_cursor);
            accumulate_pool_reward(
                rewarder,
                pool_id,
                *linked_table::borrow<ID, u128>(&rewarder_manager.pool_shares, pool_id),
                now,
            );
            pool_cursor = *linked_table::next<ID, PoolRewarderInfo>(&rewarder.pools, pool_id);
        };
    }

    fun accumulate_rewarder_released(rewarder: &mut Rewarder, now: u64) {
        if (now <= rewarder.last_reward_time) {
            return
        };
        let old_reward_time = rewarder.last_reward_time;
        rewarder.last_reward_time = now;
        if (rewarder.emission_per_second == 0) {
            return
        };
        if (rewarder.total_allocate_point == 0) {
            return
        };
        rewarder.total_reward_released =
            rewarder.total_reward_released + (full_math_u128::full_mul(rewarder.emission_per_second, ((now - old_reward_time) as u128)) as u128);
    }

    fun now_seconds(clk: &Clock): u64 {
        clk.timestamp_ms() / 1000
    }

    public(package) fun add_pool<RewardCoin>(
        rewarder_manager: &mut RewarderManager,
        pool_id: ID,
        allocate_point: u64,
        clk: &Clock,
    ) {
        assert!(is_pool_registered(rewarder_manager, pool_id), EPoolNotRegistered);
        assert!(
            !is_pool_in_rewarder(
                rewarder_manager,
                type_name::with_defining_ids<RewardCoin>(),
                pool_id,
            ),
            EPoolAlreadyInRewarder,
        );
        let now = now_seconds(clk);
        accumulate_pools_reward<RewardCoin>(rewarder_manager, now);
        let rewarder = linked_table::borrow_mut<TypeName, Rewarder>(
            &mut rewarder_manager.rewarders,
            type_name::with_defining_ids<RewardCoin>(),
        );
        accumulate_rewarder_released(rewarder, now);
        let pool_rewarder_info = PoolRewarderInfo {
            allocate_point: allocate_point,
            acc_per_share: 0,
            last_reward_time: now,
            reward_released: 0,
            reward_harvested: 0,
        };
        linked_table::push_back<ID, PoolRewarderInfo>(&mut rewarder.pools, pool_id, pool_rewarder_info);
        rewarder.total_allocate_point = rewarder.total_allocate_point + allocate_point;
    }

    public fun borrow_pool_allocate_point(
        rewarder_manager: &RewarderManager,
        rewarder_type: TypeName,
        pool_id: ID,
    ): u64 {
        assert!(
            linked_table::contains<TypeName, Rewarder>(&rewarder_manager.rewarders, rewarder_type),
            ERewarderNotExists,
        );
        assert!(
            is_pool_in_rewarder(rewarder_manager, rewarder_type, pool_id),
            EPoolNotInRewarder,
        );
        linked_table::borrow<ID, PoolRewarderInfo>(
            &linked_table::borrow<TypeName, Rewarder>(
                &rewarder_manager.rewarders,
                rewarder_type,
            ).pools,
            pool_id,
        ).allocate_point
    }

    public fun borrow_pool_rewarder_info(rewarder: &Rewarder, pool_id: ID): &PoolRewarderInfo {
        linked_table::borrow<ID, PoolRewarderInfo>(&rewarder.pools, pool_id)
    }

    public fun borrow_pool_share(rewarder_manager: &RewarderManager, pool_id: ID): u128 {
        *linked_table::borrow<ID, u128>(&rewarder_manager.pool_shares, pool_id)
    }

    public fun borrow_rewarder<RewardCoin>(rewarder_manager: &RewarderManager): &Rewarder {
        linked_table::borrow<TypeName, Rewarder>(
            &rewarder_manager.rewarders,
            type_name::with_defining_ids<RewardCoin>(),
        )
    }

    public fun create_rewarder<RewardCoin>(
        global_config: &config::GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        emission_per_second: u128,
        clk: &Clock,
        ctx: &mut TxContext,
    ) {
        config::checked_package_version(global_config);
        config::check_rewarder_manager_role(global_config, tx_context::sender(ctx));
        let reward_type = type_name::with_defining_ids<RewardCoin>();
        let rewarder = Rewarder {
            reward_coin: reward_type,
            total_allocate_point: 0,
            emission_per_second: emission_per_second,
            last_reward_time: now_seconds(clk),
            total_reward_released: 0,
            total_reward_harvested: 0,
            pools: linked_table::new<ID, PoolRewarderInfo>(ctx),
        };
        assert!(
            !linked_table::contains<TypeName, Rewarder>(&rewarder_manager.rewarders, reward_type),
            ERewarderAlreadyExists,
        );
        linked_table::push_back<TypeName, Rewarder>(&mut rewarder_manager.rewarders, reward_type, rewarder);
        let event = CreateRewarderEvent {
            reward_coin: reward_type,
            emission_per_second: emission_per_second,
        };
        emit<CreateRewarderEvent>(event);
    }

    public fun deposit_rewarder<RewardCoin>(
        global_config: &config::GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        balance: Balance<RewardCoin>,
    ) {
        config::checked_package_version(global_config);
        let reward_type = type_name::with_defining_ids<RewardCoin>();
        assert!(
            linked_table::contains<TypeName, Rewarder>(&rewarder_manager.rewarders, reward_type),
            ERewarderNotExists,
        );
        if (!bag::contains<TypeName>(&rewarder_manager.vault, reward_type)) {
            bag::add<TypeName, Balance<RewardCoin>>(
                &mut rewarder_manager.vault,
                reward_type,
                balance::zero<RewardCoin>(),
            );
        };
        let deposit_amount = balance::value<RewardCoin>(&balance);
        let event = DepositEvent {
            reward_type: reward_type,
            deposit_amount: deposit_amount,
            after_amount: balance::join<RewardCoin>(
                bag::borrow_mut<TypeName, Balance<RewardCoin>>(
                    &mut rewarder_manager.vault,
                    reward_type,
                ),
                balance,
            ),
        };
        emit<DepositEvent>(event);
    }

    public fun emergent_withdraw<RewardCoin>(
        _admin_cap: &config::AdminCap,
        _global_config: &config::GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        amount: u64,
    ): Balance<RewardCoin> {
        let reward_type = type_name::with_defining_ids<RewardCoin>();
        assert!(bag::contains<TypeName>(&rewarder_manager.vault, reward_type), EInsufficientVaultBalance);
        let vault_balance = bag::borrow_mut<TypeName, Balance<RewardCoin>>(&mut rewarder_manager.vault, reward_type);
        assert!(balance::value<RewardCoin>(vault_balance) >= amount, EInsufficientVaultBalance);
        let after_amount = balance::value<RewardCoin>(vault_balance) - amount;
        let event = EmergentWithdrawEvent {
            reward_type: reward_type,
            withdraw_amount: amount,
            after_amount,
        };
        emit<EmergentWithdrawEvent>(event);
        balance::split<RewardCoin>(vault_balance, amount)
    }

    public fun emission_per_second(rewarder_manager: &Rewarder): u128 {
        rewarder_manager.emission_per_second
    }

    fun init(otw: &mut TxContext) {
        let rewarder_manager = RewarderManager {
            id: object::new(otw),
            vault: bag::new(otw),
            pool_shares: linked_table::new<ID, u128>(otw),
            rewarders: linked_table::new<TypeName, Rewarder>(otw),
        };
        let rewarder_manager_id = object::id<RewarderManager>(&rewarder_manager);
        transfer::share_object<RewarderManager>(rewarder_manager);
        let event = InitRewarderManagerEvent { id: rewarder_manager_id };
        emit<InitRewarderManagerEvent>(event);
    }

    fun is_pool_in_rewarder(
        rewarder_manager: &RewarderManager,
        rewarder_type: TypeName,
        pool_id: ID,
    ): bool {
        linked_table::contains<ID, PoolRewarderInfo>(
            &linked_table::borrow<TypeName, Rewarder>(
                &rewarder_manager.rewarders,
                rewarder_type,
            ).pools,
            pool_id,
        )
    }

    fun is_pool_registered(rewarder_manager: &RewarderManager, pool_id: ID): bool {
        linked_table::contains<ID, u128>(&rewarder_manager.pool_shares, pool_id)
    }

    public fun last_reward_time(rewarder_manager: &Rewarder): u64 {
        rewarder_manager.last_reward_time
    }

    public fun pool_acc_per_share(info: &PoolRewarderInfo): u256 {
        info.acc_per_share
    }

    public fun pool_allocate_point(rewarder_manager: &PoolRewarderInfo): u64 {
        rewarder_manager.allocate_point
    }

    public fun pool_last_reward_time(info: &PoolRewarderInfo): u64 {
        info.last_reward_time
    }

    public fun pool_reward_harvested(info: &PoolRewarderInfo): u64 {
        info.reward_harvested
    }

    public fun pool_reward_released(info: &PoolRewarderInfo): u128 {
        info.reward_released
    }

    public(package) fun pool_rewards_settle(
        rewarder_manager: &mut RewarderManager,
        rewarder_types: vector<TypeName>,
        pool_id: ID,
        clk: &Clock,
    ): VecMap<TypeName, u256> {
        assert!(
            linked_table::contains<ID, u128>(&rewarder_manager.pool_shares, pool_id),
            EPoolShareNotRegistered,
        );
        let now = now_seconds(clk);
        let pool_share = *linked_table::borrow<ID, u128>(&rewarder_manager.pool_shares, pool_id);
        let mut idx = 0;
        let mut settled_acc_per_share = vec_map::empty<TypeName, u256>();
        while (idx < vector::length<TypeName>(&rewarder_types)) {
            let rewarder_type = *vector::borrow<TypeName>(&rewarder_types, idx);
            let rewarder = linked_table::borrow_mut<TypeName, Rewarder>(
                &mut rewarder_manager.rewarders,
                rewarder_type,
            );
            let acc_per_share = accumulate_pool_reward(
                rewarder,
                pool_id,
                pool_share,
                now,
            );
            accumulate_rewarder_released(rewarder, now);
            vec_map::insert<TypeName, u256>(&mut settled_acc_per_share, rewarder_type, acc_per_share);
            idx = idx + 1;
        };
        settled_acc_per_share
    }

    public fun pool_share(rewarder_manager: &RewarderManager, pool_id: ID): u128 {
        *linked_table::borrow<ID, u128>(&rewarder_manager.pool_shares, pool_id)
    }

    public(package) fun register_pool(rewarder_manager: &mut RewarderManager, pool_id: ID) {
        assert!(!is_pool_registered(rewarder_manager, pool_id), EPoolAlreadyRegistered);
        linked_table::push_back<ID, u128>(&mut rewarder_manager.pool_shares, pool_id, 0);
    }

    public(package) fun set_pool<RewardCoin>(
        rewarder_manager: &mut RewarderManager,
        pool_id: ID,
        allocate_point: u64,
        clk: &Clock,
    ): u256 {
        assert!(is_pool_registered(rewarder_manager, pool_id), EPoolNotRegistered);
        assert!(
            is_pool_in_rewarder(
                rewarder_manager,
                type_name::with_defining_ids<RewardCoin>(),
                pool_id,
            ),
            EPoolNotInRewarder,
        );
        let now = now_seconds(clk);
        accumulate_pools_reward<RewardCoin>(rewarder_manager, now);
        let rewarder = linked_table::borrow_mut<TypeName, Rewarder>(
            &mut rewarder_manager.rewarders,
            type_name::with_defining_ids<RewardCoin>(),
        );
        accumulate_rewarder_released(rewarder, now);
        let pool_rewarder_info = linked_table::borrow_mut<ID, PoolRewarderInfo>(&mut rewarder.pools, pool_id);
        rewarder.total_allocate_point = rewarder.total_allocate_point - pool_rewarder_info.allocate_point + allocate_point;
        pool_rewarder_info.allocate_point = allocate_point;
        pool_rewarder_info.acc_per_share
    }

    public(package) fun set_pool_share(
        rewarder_manager: &mut RewarderManager,
        pool_id: ID,
        share: u128,
    ) {
        *linked_table::borrow_mut<ID, u128>(&mut rewarder_manager.pool_shares, pool_id) = share;
    }

    public fun total_allocate_point(rewarder_manager: &Rewarder): u64 {
        rewarder_manager.total_allocate_point
    }

    public fun total_reward_harvested(rewarder: &Rewarder): u64 {
        rewarder.total_reward_harvested
    }

    public fun total_reward_released(rewarder: &Rewarder): u128 {
        rewarder.total_reward_released
    }

    public fun update_rewarder<RewardCoin>(
        global_config: &config::GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        emission_per_second: u128,
        clk: &Clock,
        ctx: &TxContext,
    ) {
        config::checked_package_version(global_config);
        config::check_rewarder_manager_role(global_config, tx_context::sender(ctx));
        assert!(
            linked_table::contains<TypeName, Rewarder>(
                &rewarder_manager.rewarders,
                type_name::with_defining_ids<RewardCoin>(),
            ),
            ERewarderNotExists,
        );
        let reward_type = type_name::with_defining_ids<RewardCoin>();
        let now = now_seconds(clk);
        accumulate_pools_reward<RewardCoin>(rewarder_manager, now);
        let rewarder = linked_table::borrow_mut<TypeName, Rewarder>(&mut rewarder_manager.rewarders, reward_type);
        accumulate_rewarder_released(rewarder, now);
        rewarder.emission_per_second = emission_per_second;
        let event = UpdateRewarderEvent {
            reward_coin: reward_type,
            emission_per_second: emission_per_second,
        };
        emit<UpdateRewarderEvent>(event);
    }

    public fun vault_balance<RewardCoin>(rewarder_manager: &RewarderManager): u64 {
        balance::value<RewardCoin>(
            bag::borrow<TypeName, Balance<RewardCoin>>(
                &rewarder_manager.vault,
                type_name::with_defining_ids<RewardCoin>(),
            ),
        )
    }

    public(package) fun withdraw_reward<RewardCoin>(
        rewarder_manager: &mut RewarderManager,
        pool_id: ID,
        amount: u64,
    ): Balance<RewardCoin> {
        let reward_type = type_name::with_defining_ids<RewardCoin>();
        assert!(is_pool_registered(rewarder_manager, pool_id), EPoolNotRegistered);
        assert!(
            is_pool_in_rewarder(
                rewarder_manager,
                reward_type,
                pool_id,
            ),
            EPoolNotInRewarder,
        );
        assert!(
            bag::contains<TypeName>(
                &rewarder_manager.vault,
                reward_type,
            ),
            EInsufficientVaultBalance,
        );
        let vault_balance = bag::borrow_mut<TypeName, Balance<RewardCoin>>(
            &mut rewarder_manager.vault,
            reward_type,
        );
        assert!(balance::value<RewardCoin>(vault_balance) >= amount, EInsufficientVaultBalance);
        let rewarder = linked_table::borrow_mut<TypeName, Rewarder>(
            &mut rewarder_manager.rewarders,
            reward_type,
        );
        rewarder.total_reward_harvested = rewarder.total_reward_harvested + amount;
        let pool_rewarder_info = linked_table::borrow_mut<ID, PoolRewarderInfo>(&mut rewarder.pools, pool_id);
        pool_rewarder_info.reward_harvested = pool_rewarder_info.reward_harvested + amount;
        assert!(
            pool_rewarder_info.reward_released >= (pool_rewarder_info.reward_harvested as u128),
            EHarvestExceedsReleased,
        );
        assert!(
            rewarder.total_reward_released >= (rewarder.total_reward_harvested as u128),
            EHarvestExceedsReleased,
        );
        balance::split<RewardCoin>(vault_balance, amount)
    }

    #[test_only]
    public fun new_manager_for_testing(ctx: &mut TxContext): RewarderManager {
        RewarderManager {
            id: object::new(ctx),
            vault: bag::new(ctx),
            pool_shares: linked_table::new<ID, u128>(ctx),
            rewarders: linked_table::new<TypeName, Rewarder>(ctx),
        }
    }
}
