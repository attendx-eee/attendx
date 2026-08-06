enum EnrollmentFlowState {
  warmingUp,

  lowLight,

  waitingForFace,

  aligningFace,

  waitingForBlink,

  livenessVerified,

  waitingForPose,

  waitingForStability,

  capturing,

  processing,

  changingPose,

  checkingDuplicate,

  uploading,

  completed,

  failed,
}