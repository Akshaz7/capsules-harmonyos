import localUnitTest from './LocalUnit.test';
import capsuleValidatorTest from './CapsuleValidator.test';
import ruleParserTest from './RuleParser.test';
import capsuleModelTest from './CapsuleModel.test';
import capsuleGeneratorTest from './CapsuleGenerator.test';
import capsuleRouterTest from './CapsuleRouter.test';

export default function testsuite() {
  localUnitTest();
  capsuleValidatorTest();
  ruleParserTest();
  capsuleModelTest();
  capsuleGeneratorTest();
  capsuleRouterTest();
}
