import localUnitTest from './LocalUnit.test';
import capsuleValidatorTest from './CapsuleValidator.test';
import ruleParserTest from './RuleParser.test';

export default function testsuite() {
  localUnitTest();
  capsuleValidatorTest();
  ruleParserTest();
}
