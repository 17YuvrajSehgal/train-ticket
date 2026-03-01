package auth.service;

import auth.dto.BasicAuthDto;
import auth.entity.User;
import auth.exception.UserOperationException;
import auth.security.jwt.JWTProvider;
import auth.service.impl.TokenServiceImpl;
import edu.fudan.common.util.Response;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.JUnit4;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.MockitoAnnotations;
import org.springframework.http.*;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.web.client.RestTemplate;

@RunWith(JUnit4.class)
public class TokenServiceImplTest {

    @InjectMocks
    private TokenServiceImpl tokenServiceImpl;

    @Mock
    private RestTemplate restTemplate;

    @Mock
    private JWTProvider jwtProvider;

    @Mock
    private AuthenticationManager authenticationManager;

    private HttpHeaders headers = new HttpHeaders();
    HttpEntity requestEntity = new HttpEntity(headers);

    @Before
    public void setUp() {
        MockitoAnnotations.initMocks(this);
    }

    @Test
    public void testGetToken1() {
        BasicAuthDto dto = new BasicAuthDto(null, null, "verifyCode");
        ResponseEntity<Boolean> re = new ResponseEntity<>(false, HttpStatus.OK);
        Mockito.when(restTemplate.exchange(
                "http://ts-verification-code-service:15678/api/v1/verifycode/verify/" + "verifyCode",
                HttpMethod.GET,
                requestEntity,
                Boolean.class)).thenReturn(re);
        Response result = tokenServiceImpl.getToken(dto, headers);
        Assert.assertEquals(new Response<>(0, "Verification failed.", null), result);
    }

    @Test
    public void testGetToken2() throws UserOperationException {
        BasicAuthDto dto = new BasicAuthDto("username", null, "");
        User user = new User();
        Authentication auth = Mockito.mock(Authentication.class);
        Mockito.when(auth.getPrincipal()).thenReturn(user);
        Mockito.when(authenticationManager.authenticate(Mockito.any(UsernamePasswordAuthenticationToken.class))).thenReturn(auth);
        Mockito.when(jwtProvider.createToken(user)).thenReturn("token");
        Response result = tokenServiceImpl.getToken(dto, headers);
        Assert.assertEquals("login success", result.getMsg());
    }

}
