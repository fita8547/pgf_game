/// Original agent roster. Every agent has a purchasable Q and a signature E.
enum AgentId { rift, shroud, flare, mend }

enum AbilityKind { dash, smoke, flash, recon, heal, barrier }

class AbilityDef {
  final AbilityKind kind;
  final String name;
  final String desc;

  /// Credits per charge (0 = not purchasable).
  final int cost;
  final int maxCharges;

  /// Charges granted for free at round start.
  final int freeCharges;

  /// Seconds to regain a free charge mid-round (0 = never).
  final double recharge;
  const AbilityDef(this.kind, this.name, this.desc,
      {this.cost = 0, this.maxCharges = 1, this.freeCharges = 0, this.recharge = 0});
}

class AgentDef {
  final AgentId id;
  final String name;
  final String role;
  final String bio;

  /// ARGB accent color.
  final int color;
  final AbilityDef q;
  final AbilityDef e;
  const AgentDef(this.id, this.name, this.role, this.bio, this.color, this.q, this.e);
}

const flashAbility = AbilityDef(AbilityKind.flash, 'Glare', 'Throw a bouncing flare that blinds anyone looking at it.',
    cost: 250, maxCharges: 2);

const Map<AgentId, AgentDef> agents = {
  AgentId.rift: AgentDef(
    AgentId.rift,
    'Rift',
    'Duelist',
    'Aggressive entry fragger who slips through space.',
    0xFFFF6B3D,
    flashAbility,
    AbilityDef(AbilityKind.dash, 'Slipstream', 'Instantly dash in your movement direction.',
        freeCharges: 1, maxCharges: 1),
  ),
  AgentId.shroud: AgentDef(
    AgentId.shroud,
    'Shroud',
    'Controller',
    'Cuts sightlines with long lasting vapor clouds.',
    0xFF8E7CFF,
    AbilityDef(AbilityKind.smoke, 'Vapor', 'Throw a smoke canister that blocks vision.',
        cost: 150, maxCharges: 2),
    AbilityDef(AbilityKind.smoke, 'Deep Vapor', 'Free smoke that recharges.',
        freeCharges: 1, maxCharges: 1, recharge: 35),
  ),
  AgentId.flare: AgentDef(
    AgentId.flare,
    'Flare',
    'Initiator',
    'Gathers intel and blinds defenders before the push.',
    0xFFFFC93D,
    flashAbility,
    AbilityDef(AbilityKind.recon, 'Echo Pulse', 'Throw a pulse that reveals nearby enemies.',
        freeCharges: 1, maxCharges: 1, recharge: 40),
  ),
  AgentId.mend: AgentDef(
    AgentId.mend,
    'Mend',
    'Sentinel',
    'Holds ground with barriers and keeps the team alive.',
    0xFF3DFFB5,
    AbilityDef(AbilityKind.barrier, 'Bulwark', 'Raise a temporary wall in front of you.',
        cost: 300, maxCharges: 1),
    AbilityDef(AbilityKind.heal, 'Renew', 'Heal yourself or an ally you look at for 60 HP.',
        freeCharges: 1, maxCharges: 1, recharge: 40),
  ),
};
