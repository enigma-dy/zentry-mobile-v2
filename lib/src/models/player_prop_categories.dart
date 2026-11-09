class PlayerPropCategory {
  final String statType;
  final String label;
  const PlayerPropCategory(this.statType, this.label);
}

const playerPropCategories = [
  PlayerPropCategory('', 'All'),
  PlayerPropCategory('shots_on_target', 'Shots on Target'),
  PlayerPropCategory('shots', 'Total Shots'),
  PlayerPropCategory('tackles', 'Tackles'),
  PlayerPropCategory('passes', 'Passes'),
  PlayerPropCategory('fouls_won', 'Fouls Won'),
  PlayerPropCategory('fouls_committed', 'Fouls Committed'),
  PlayerPropCategory('assists', 'Assists'),
  PlayerPropCategory('goals', 'Goals'),
  PlayerPropCategory('saves', 'Saves'),
];
